'use client'

import { useCallback, useSyncExternalStore } from 'react'
import { Check, Rows3, SlidersHorizontal, LayoutGrid, Grid3x3, List } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuItem,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu'

type FontChoice = 'normal' | 'rounded' | 'system'
type LayoutChoice = 'standard' | 'compact' | 'dense' | 'list'

const FONT_KEY = 'papergrid.font'
const LAYOUT_KEY = 'papergrid.postLayout'
const FONT_VALUES: FontChoice[] = ['normal', 'rounded', 'system']
const LAYOUT_VALUES: LayoutChoice[] = ['standard', 'compact', 'dense', 'list']

const FONTS: { value: FontChoice; label: string }[] = [
  { value: 'normal', label: '正常字体' },
  { value: 'rounded', label: '圆体（原版风格）' },
  { value: 'system', label: '系统字体' },
]

const LAYOUTS: { value: LayoutChoice; label: string }[] = [
  { value: 'standard', label: '两列卡片' },
  { value: 'compact', label: '三列卡片' },
  { value: 'dense', label: '四列卡片' },
  { value: 'list', label: '列表模式' },
]

/* localStorage 作为单一数据源：useSyncExternalStore 保证 SSR 安全且无水合警告。 */
const prefListeners = new Set<() => void>()
function emitPrefChange() {
  prefListeners.forEach((listener) => listener())
}
function subscribePrefs(onStoreChange: () => void) {
  prefListeners.add(onStoreChange)
  window.addEventListener('storage', onStoreChange)
  return () => {
    prefListeners.delete(onStoreChange)
    window.removeEventListener('storage', onStoreChange)
  }
}

function readFont(): FontChoice {
  try {
    const saved = localStorage.getItem(FONT_KEY) as FontChoice | null
    return saved && FONT_VALUES.includes(saved) ? saved : 'normal'
  } catch {
    return 'normal'
  }
}
function readLayout(): LayoutChoice {
  try {
    const saved = localStorage.getItem(LAYOUT_KEY) as LayoutChoice | null
    return saved && LAYOUT_VALUES.includes(saved) ? saved : 'standard'
  } catch {
    return 'standard'
  }
}

function applyFont(value: FontChoice) {
  const root = document.documentElement
  if (value === 'normal') root.removeAttribute('data-font')
  else root.setAttribute('data-font', value)
}

function applyLayout(value: LayoutChoice) {
  const root = document.documentElement
  if (value === 'standard') root.removeAttribute('data-post-layout')
  else root.setAttribute('data-post-layout', value)
}

/** 显示偏好：字体方案 + 卡片版式。选择保存在 localStorage，刷新后仍然生效。 */
export function DisplayPreferences() {
  const font = useSyncExternalStore(subscribePrefs, readFont, () => 'normal' as FontChoice)
  const layout = useSyncExternalStore(subscribePrefs, readLayout, () => 'standard' as LayoutChoice)

  const chooseFont = useCallback((value: FontChoice) => {
    applyFont(value)
    try {
      localStorage.setItem(FONT_KEY, value)
    } catch {
      /* 隐私模式等场景下不可写，忽略即可 */
    }
    emitPrefChange()
  }, [])

  const chooseLayout = useCallback((value: LayoutChoice) => {
    applyLayout(value)
    try {
      localStorage.setItem(LAYOUT_KEY, value)
    } catch {
      /* 同上 */
    }
    emitPrefChange()
  }, [])

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" aria-label="显示偏好：字体与卡片版式">
          <SlidersHorizontal className="h-4 w-4" aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-44">
        <DropdownMenuLabel>字体</DropdownMenuLabel>
        {FONTS.map((option) => (
          <DropdownMenuItem key={option.value} onSelect={() => chooseFont(option.value)}>
            <TypeGlyph value={option.value} />
            <span className="mr-auto">{option.label}</span>
            {font === option.value && <Check className="h-4 w-4" aria-hidden="true" />}
          </DropdownMenuItem>
        ))}
        <DropdownMenuSeparator />
        <DropdownMenuLabel>卡片版式</DropdownMenuLabel>
        {LAYOUTS.map((option) => (
          <DropdownMenuItem key={option.value} onSelect={() => chooseLayout(option.value)}>
            <LayoutGlyph value={option.value} />
            <span className="mr-auto">{option.label}</span>
            {layout === option.value && <Check className="h-4 w-4" aria-hidden="true" />}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function TypeGlyph({ value }: { value: FontChoice }) {
  return (
    <span
      aria-hidden="true"
      className="flex h-4 w-4 items-center justify-center text-[13px] font-semibold leading-none"
      style={{
        fontFamily:
          value === 'system'
            ? 'system-ui, sans-serif'
            : value === 'rounded'
              ? "'PaperGrid Rounded', sans-serif"
              : "'Noto Sans SC Variable', sans-serif",
      }}
    >
      字
    </span>
  )
}

function LayoutGlyph({ value }: { value: LayoutChoice }) {
  const className = 'h-4 w-4'
  if (value === 'compact') return <Grid3x3 className={className} aria-hidden="true" />
  if (value === 'dense') return <Rows3 className={className} aria-hidden="true" />
  if (value === 'list') return <List className={className} aria-hidden="true" />
  return <LayoutGrid className={className} aria-hidden="true" />
}
