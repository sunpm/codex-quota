---
name: Codex Quota
description: 简洁、紧凑的 macOS 与 Windows 额度和用量工具。
colors:
  background-light: "#fafafa"
  foreground-light: "#252629"
  card-light: "#fff"
  popover-light: "#fff"
  sidebar-light: "#f2f3f4"
  primary-light: "#286fae"
  primary-foreground-light: "#fff"
  secondary-light: "#eceef0"
  accent-light: "#e6e9ed"
  muted-light: "#686c72"
  border-light: "#dedfe2"
  input-light: "#d7d9dd"
  destructive-light: "#bd354b"
  chart-text-light: "#666b72"
  quota-normal-light: "#63798c"
  quota-warning-light: "#ae661f"
  quota-exhausted-light: "#bd354b"
  warning-surface-light: "#fff7ec"
  warning-text-light: "#86531e"
  background-dark: "#202124"
  foreground-dark: "#e9eaed"
  card-dark: "#26272b"
  popover-dark: "#2d2f33"
  sidebar-dark: "#1b1c1f"
  primary-dark: "#4389c7"
  primary-foreground-dark: "#fff"
  secondary-dark: "#323439"
  accent-dark: "#393b42"
  muted-dark: "#a3a7af"
  border-dark: "#3c3e44"
  input-dark: "#4c4f57"
  destructive-dark: "#e47786"
  chart-text-dark: "#a3a7af"
  quota-normal-dark: "#96adbf"
  quota-warning-dark: "#e5a05b"
  quota-exhausted-dark: "#e47786"
  warning-surface-dark: "#352e26"
  warning-text-dark: "#e5b983"
  chart-blue: "#3279bd"
  chart-teal: "#448d86"
  chart-amber: "#ad8044"
  chart-purple: "#9e6686"
  composition: "#5d8b9e"
  heatmap-low: "#a3d1ca"
  heatmap-mid: "#679e94"
  heatmap-high: "#33786c"
  chart-quota-normal: "#647d93"
  chart-quota-warning: "#b87530"
  chart-quota-exhausted: "#c33f53"
  unpriced: "#ab743e"
typography:
  caption:
    fontFamily: "system-ui"
    fontSize: "10px"
    fontWeight: 400
  small:
    fontFamily: "system-ui"
    fontSize: "11px"
    fontWeight: 400
  detail:
    fontFamily: "system-ui"
    fontSize: "12px"
    fontWeight: 400
  control:
    fontFamily: "system-ui"
    fontSize: "13px"
    fontWeight: 400
  dialog-title:
    fontFamily: "system-ui"
    fontSize: "16px"
    fontWeight: 600
  page-title:
    fontFamily: "system-ui"
    fontSize: "18px"
    fontWeight: 600
  compact-value:
    fontFamily: "system-ui"
    fontSize: "21px"
    fontWeight: 600
  responsive-value:
    fontFamily: "system-ui"
    fontSize: "23px"
    fontWeight: 600
  quota-value:
    fontFamily: "system-ui"
    fontSize: "24px"
    fontWeight: 600
  usage-value:
    fontFamily: "system-ui"
    fontSize: "25px"
    fontWeight: 600
rounded:
  cell: "2px"
  progress: "3px"
  control-small: "4px"
  selection: "5px"
  control: "6px"
  selection-track: "7px"
  card: "10px"
  large: "12px"
spacing:
  tight: "4px"
  related: "8px"
  compact: "12px"
  section: "16px"
  surface: "18px"
  page: "24px"
components:
  surface:
    rounded: "{rounded.card}"
    padding: "{spacing.surface}"
  sidebar-item:
    rounded: "{rounded.control}"
    typography: "{typography.control}"
    height: "36px"
  metric-value:
    typography: "{typography.usage-value}"
---

# Design System: Codex Quota

## Overview

沿用现有桌面工具的视觉秩序：稳定的侧栏、紧凑的数字、清晰的表格和图表。此次将 SwiftUI / AppKit 界面迁移为 Tauri WebView 内的 Vue 3、shadcn-vue 与 Apache ECharts，保持用量统计、对话、项目、额度、设置五个入口。不是品牌重设计。

实际样式源为 `src/style.css`，交互源为 `src/App.vue` 与 `src/components/`。`src/components/ui/` 由 shadcn-vue CLI 生成；使用其 size、variant 接口和主题变量，覆盖放在调用层或样式源中，不手改生成组件。图标采用当前官方 `@lucide/vue` 包，统一线性图标。

## Colors

界面跟随操作系统浅深色。背景、内容表面、侧栏、边框、主文字和次要文字分别使用语义变量。蓝色用于选中导航、单选项与提交动作；额度的正常、预警、耗尽状态独立使用灰蓝、橙和红，并保留实际数字。颜色不能把未知数据伪装为正常。

图表按需引入 ECharts 模块。热力图用低至高的青绿色量阶，未定价费用用虚线边界和提示说明；金额缺失不显示为零。系统字体和图表字体遵循系统外观，不加载远程字体。

## Typography

基础字号 13px，表格与辅助信息 12px，页标题 18px。主要统计值 25px，紧凑汇总 21px，额度值 24px。较小字号只用于短 ID、图例和版本。数据、金额、百分比、时间使用 tabular-nums；模型与短 ID 使用等宽字体。正文、按钮和导航不使用技术装饰字体。

## Layout

初始侧栏 178px，可通过分隔线拖动或方向键调至 168–300px。主窗口内容边距 24px，960px 以下收为 18px；页面最小布局宽度 760px。标题栏高 66px，侧栏今日指标固定底部。概览页纵向滚动；对话和项目页的表格填满剩余高度并独立滚动。960px 以下隐藏表格次要目录/时间列，完整值保留悬停入口；详情表格可横向滚动。

## Components

普通操作使用 shadcn-vue `Button` 的 outline、ghost 和 sm；保存、完成使用默认强调样式，清除确认使用 destructive。焦点外框与控件实际布局独立，不用偏移抵消视觉外扩。

日期范围、Tokens/费用和额度趋势范围使用原生 radio 加选中背景，支持 Tab 与方向键。模型和刷新间隔使用原生 select；自定义日期使用原生 date 输入；自定义刷新间隔使用带原生 number 输入的 Popover，最小 30 秒，保存生效，取消和 Esc 放弃。

设置项保持左侧标签、右侧控件。额度监测关闭时，依赖设置一起禁用和淡化，菜单栏/托盘、登录启动与用量扫描保持独立。多选指标和列选项采用 Popover + Checkbox，连续选择立即保存。对话明细、价格编辑与清除确认使用 Dialog，保留标题、说明和完成/取消动作。

## Data presentation

本机扫描时间与来源在筛选下方显示，警告放在汇总前。API 等价费用不代表订阅账单；部分缺价使用“已定价费用”，全无定价显示“未定价”。前端只聚合 Rust 返回的十进制费用字符串，不重新实现定价规则。同期比较仅在概览显示；当前未结束的时间范围按本地时刻对齐上期。

额度页没有刷新按钮、更新时间或加载占位；切换进入页面会请求刷新，读取失败保留已有读数并标为过期。倒计时本地计算，归零显示等待实际重置。额度折线按后端 segment 分段，重置或观测中断处不连线。公开重置动态与个人额度分开，最多展示最近三条，链接经 Rust 检查后打开。

## Motion and accessibility

界面过渡使用短时状态变化，图表动画 220ms。应用动画开关和系统减少动态效果均能关闭动画。系统浅深色变化会重新应用 ECharts 主题，图表容器通过 ResizeObserver 调整尺寸并在卸载时释放。

原生表单控件保留标签、键盘行为及焦点样式。图标动作保留名称；图表具有文字辅助说明和对应汇总数字。页面支持平台常用刷新与设置快捷键，原生菜单事件与页面动作共用业务命令。

## Evidence and constraints

迁移依据为当前 Swift 源码、README、PRODUCT 和旧版额度/设置截图。旧截图包含已取消的刷新按钮与更新时间，不作为当前行为依据。`?preview` 使用明确标注的匿名离线示例，仅用于界面验收；普通浏览器环境不会尝试读取本机凭据或伪造服务成功。

本次类型检查和生产构建已通过。Chrome 的关键流程验收由专门代理记录，桌面系统集成与 Windows 实机检查的证据由主代理汇总；本文件不把源码支持或离线预览写成跨平台实测通过。
