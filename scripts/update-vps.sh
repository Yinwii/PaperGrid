#!/usr/bin/env bash
# PaperGrid VPS 一键更新脚本
#
# 用法（在 VPS 上的仓库目录执行）：
#   ./scripts/update-vps.sh                # 自动识别部署方式并更新到最新代码
#   MODE=build ./scripts/update-vps.sh      # 强制本地构建镜像（推荐：包含本仓库全部改动）
#   MODE=pull  ./scripts/update-vps.sh      # 强制从镜像仓库拉取（仅当镜像由你的仓库构建时有效）
#   ALLOW_STASH=1 ./scripts/update-vps.sh   # 工作区有改动时自动 git stash
#
# 行为：
#   1) 识别当前容器的镜像来源与宿主端口（保持端口不变，避免打断 Nginx）
#   2) git fetch + 快进合并到 origin 的当前分支
#   3) 尽力备份数据卷中的 SQLite 数据库
#   4) 本地构建或拉取镜像，然后重启容器
#   5) 健康检查，失败时输出日志与回滚指引
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONTAINER="${CONTAINER:-papergrid}"
MODE="${MODE:-auto}"                                  # auto | build | pull
COMPOSE_PULL_FILE="${COMPOSE_PULL_FILE:-docker-compose.yml}"
COMPOSE_BUILD_FILE="${COMPOSE_BUILD_FILE:-docker-compose.build.yml}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-120}"
HEALTH_PATH="${HEALTH_PATH:-/}"

c_info() { printf '\033[36m[update]\033[0m %s\n' "$*"; }
c_ok() { printf '\033[32m[update]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[33m[update]\033[0m %s\n' "$*"; }
c_error() { printf '\033[31m[update]\033[0m %s\n' "$*" >&2; }

DRY_RUN="${DRY_RUN:-0}"       # 1 = 只打印将要执行的动作，不改动任何东西

require() {
  command -v "$1" >/dev/null 2>&1 || {
    c_error "缺少命令：$1"
    exit 1
  }
}

require git
require curl
if [[ "$DRY_RUN" == "1" ]]; then
  c_warn "DRY_RUN=1：仅预览，不会构建、重启或改动任何文件。"
else
  require docker
  docker compose version >/dev/null 2>&1 || {
    c_error "需要 Docker Compose v2（docker compose）"
    exit 1
  }
  [[ -f "$COMPOSE_BUILD_FILE" ]] || {
    c_error "未找到 $COMPOSE_BUILD_FILE"
    exit 1
  }
fi

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[35m  [dry-run]\033[0m %s\n' "$*"
  else
    "$@"
  fi
}

stamp="$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------- 1. 识别形态
image_ref=""
host_port=""
old_commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ "$DRY_RUN" != "1" ]] && docker inspect "$CONTAINER" >/dev/null 2>&1; then
  image_ref="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")"
  host_port="$(docker port "$CONTAINER" 3000/tcp 2>/dev/null | head -n1 | sed 's/.*://')"
fi

if [[ -z "$host_port" ]]; then
  # 未检测到运行中的容器时，沿用 .env 或默认端口
  host_port="${APP_PORT:-6066}"
fi
export APP_PORT="${APP_PORT:-$host_port}"
c_info "当前容器镜像：${image_ref:-未检测到}  宿主端口：${APP_PORT}"

if [[ "$MODE" == auto ]]; then
  case "$image_ref" in
    ghcr.io/xywml/*)
      MODE=build
      c_warn "上游镜像 $image_ref 由原项目构建，不包含本仓库的改动 → 自动选择本地构建。"
      c_warn "若你确实使用上游镜像，可加 MODE=pull 强制拉取。"
      ;;
    "")
      MODE=build
      c_info "未检测到运行中的容器，默认本地构建。"
      ;;
    *)
      MODE=pull
      ;;
  esac
fi
c_info "更新方式：$MODE"

# ---------------------------------------------------------------- 2. 拉取代码
if git rev-parse --git-dir >/dev/null 2>&1; then
  branch="$(git rev-parse --abbrev-ref HEAD)"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    if [[ "${ALLOW_STASH:-0}" == "1" ]]; then
      c_warn "检测到本地改动，按 ALLOW_STASH=1 暂存到 stash：update-vps-$stamp"
      git stash push -u -m "update-vps-$stamp" >/dev/null
    else
      c_error "工作区有未提交改动，已停止。请先提交或暂存，或使用 ALLOW_STASH=1 自动暂存。"
      git status --short | head -20
      exit 1
    fi
  fi
  c_info "从 origin/$branch 拉取最新代码..."
  git fetch --prune origin
  git merge --ff-only "origin/$branch" || {
    c_error "无法快进合并 origin/$branch，请手动处理分叉后重试。"
    exit 1
  }
else
  c_warn "当前目录不是 git 仓库，跳过代码拉取（仅重建镜像）。"
fi
new_commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ "$old_commit" == "$new_commit" ]]; then
  c_info "代码已是最新（$new_commit）。"
else
  c_ok "代码更新：$old_commit → $new_commit"
fi

# ---------------------------------------------------------------- 3. 备份数据
mkdir -p "$BACKUP_DIR"
if [[ "$DRY_RUN" != "1" ]] && docker inspect "$CONTAINER" >/dev/null 2>&1; then
  c_info "尽力备份数据卷（容器运行中，属热备份）..."
  for name in db.sqlite ai-index.sqlite; do
    target="$BACKUP_DIR/${name%.sqlite}-$stamp.sqlite"
    if docker cp "$CONTAINER:/data/$name" "$target" 2>/dev/null; then
      c_ok "已备份 /data/$name → $target"
    fi
  done
  docker cp "$CONTAINER:/data/initial-admin.txt" "$BACKUP_DIR/initial-admin-$stamp.txt" 2>/dev/null || true
fi

# ---------------------------------------------------------------- 4. 构建/拉取并重启
if [[ "$MODE" == "build" ]]; then
  c_info "本地构建镜像（首次或依赖变化时较慢，请耐心等待）..."
  run docker compose -f "$COMPOSE_BUILD_FILE" build --pull
  run docker compose -f "$COMPOSE_BUILD_FILE" up -d
else
  c_info "拉取镜像并重启..."
  run docker compose -f "$COMPOSE_PULL_FILE" pull
  run docker compose -f "$COMPOSE_PULL_FILE" up -d
fi

# ---------------------------------------------------------------- 5. 健康检查
if [[ "$DRY_RUN" == "1" ]]; then
  c_ok "预览结束（未做任何改动）。去掉 DRY_RUN 即可真正执行。"
  exit 0
fi

url="http://127.0.0.1:${APP_PORT}${HEALTH_PATH}"
c_info "健康检查：$url"
deadline=$(( $(date +%s) + HEALTH_TIMEOUT ))
until curl -fsS -o /dev/null "$url" 2>/dev/null; do
  if (( $(date +%s) > deadline )); then
    c_error "健康检查超时（${HEALTH_TIMEOUT}s），容器最近日志："
    docker logs --tail 60 "$CONTAINER" || true
    c_warn "回滚指引："
    c_warn "  1) git reset --hard $old_commit"
    c_warn "  2) 用 $BACKUP_DIR 中 ${stamp} 的备份恢复数据库"
    c_warn "  3) 重新执行本脚本"
    exit 1
  fi
  sleep 3
done

c_ok "更新完成 ✔"
c_ok "版本：$old_commit → $new_commit"
c_ok "镜像：$(docker inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null || echo "$image_ref")"
c_info "如需清理旧镜像：docker image prune -f"
