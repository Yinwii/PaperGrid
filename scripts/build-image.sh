#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(node -p "require('${ROOT_DIR}/package.json').version")"

if [[ -z "${VERSION}" ]]; then
  echo "未能读取应用版本号" >&2
  exit 1
fi

IMAGE="${IMAGE:-}"
if [[ -z "${IMAGE}" ]]; then
  # 未显式指定时，按本仓库所属账号推导镜像地址（GHCR 要求小写）。
  OWNER="$(git -C "${ROOT_DIR}" config --get remote.origin.url 2>/dev/null \
    | sed -E 's#.*[:/]([^/]+)/[^/]+$#\1#; s#\.git$##' \
    | tr '[:upper:]' '[:lower:]')"
  IMAGE="ghcr.io/${OWNER:-xywml}/papergrid"
  echo "未指定 IMAGE，按远端仓库推导为: ${IMAGE}"
fi
TAG_VERSION="${VERSION}"
if [[ "${TAG_VERSION}" != v* ]]; then
  TAG_VERSION="v${TAG_VERSION}"
fi

echo "使用版本: ${TAG_VERSION}"
docker build \
  --build-arg APP_VERSION="${VERSION}" \
  -t "${IMAGE}:${TAG_VERSION}" \
  -t "${IMAGE}:latest" \
  "${ROOT_DIR}"
