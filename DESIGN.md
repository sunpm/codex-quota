---
name: "Codex Quota"
description: "查看 Codex 与 Antigravity 剩余额度和本地用量的桌面仪表盘。"
colors:
  background-light: "#fafafa"
  background-dark: "#18191c"
  foreground-light: "#252629"
  foreground-dark: "#e9eaed"
  sidebar-light: "#f2f3f4"
  sidebar-dark: "#131417"
  card-light: "#fff"
  card-dark: "#202125"
  popover-light: "#fff"
  popover-dark: "#27292e"
  border-light: "#dedfe2"
  border-dark: "#34363d"
  input-light: "#d7d9dd"
  input-dark: "#424650"
  secondary-light: "#eceef0"
  secondary-dark: "#2a2c31"
  muted-light: "#686c72"
  muted-dark: "#a3a7af"
  accent-light: "#e6e9ed"
  accent-dark: "#32353b"
  primary-light: "#286fae"
  primary-dark: "#3178b7"
  primary-foreground-light: "#fff"
  primary-foreground-dark: "#fff"
  destructive-light: "#bd354b"
  destructive-dark: "#e47786"
  usage-increase-light: "#bd354b"
  usage-increase-dark: "#e47786"
  usage-decrease-light: "#287448"
  usage-decrease-dark: "#78c99a"
  chart-text-light: "#666b72"
  chart-text-dark: "#a3a7af"
  quota-normal-light: "#63798c"
  quota-normal-dark: "#96adbf"
  quota-warning-light: "#ae661f"
  quota-warning-dark: "#e5a05b"
  quota-exhausted-light: "#bd354b"
  quota-exhausted-dark: "#e47786"
  deadline-normal-light: "#287448"
  deadline-normal-dark: "#78c99a"
  deadline-warning-light: "#866a08"
  deadline-warning-dark: "#dfc55b"
  deadline-urgent-light: "#b45214"
  deadline-urgent-dark: "#efa063"
  deadline-critical-light: "#bd354b"
  deadline-critical-dark: "#e47786"
  unpriced-light: "#ab743e"
  unpriced-dark: "#e5a05b"
  warning-surface-light: "#fff7ec"
  warning-surface-dark: "#2d2620"
  warning-text-light: "#86531e"
  warning-text-dark: "#e5b983"
  service-codex: "#3279bd"
  service-antigravity: "#448d86"
  heatmap-low: "#a3d1ca"
  heatmap-mid: "#679e94"
  heatmap-high: "#33786c"
  chart-quota-normal: "#647d93"
  chart-quota-warning: "#b87530"
  chart-quota-exhausted: "#c33f53"
typography:
  usage-value:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "30px"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "-0.025em"
  quota-value:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "22px"
    fontWeight: 600
  page-title:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "18px"
    fontWeight: 600
    letterSpacing: "-0.2px"
  dialog-title:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "16px"
    fontWeight: 600
  summary-detail:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "14px"
    fontWeight: 600
  section-title:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "13px"
    fontWeight: 600
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "13px"
    fontWeight: 400
  detail:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "12px"
    fontWeight: 400
  monospace:
    fontFamily: "ui-monospace, SFMono-Regular, Consolas, monospace"
    fontSize: "11px"
    fontWeight: 400
  caption:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "10px"
    fontWeight: 500
rounded:
  cell: "2px"
  progress: "3px"
  tag: "4px"
  selection: "5px"
  control: "6px"
  selection-track: "7px"
  card: "10px"
spacing:
  tight: "4px"
  related: "8px"
  compact: "12px"
  section: "16px"
  surface: "18px"
  page: "24px"
components:
  button-primary:
    backgroundColor: "{colors.primary-light}"
    textColor: "{colors.primary-foreground-light}"
    rounded: "{rounded.control}"
    height: "32px"
    padding: "4px 12px"
  button-outline:
    backgroundColor: "{colors.background-light}"
    textColor: "{colors.foreground-light}"
    rounded: "{rounded.control}"
    height: "28px"
    padding: "3px 10px"
  button-ghost:
    textColor: "{colors.foreground-light}"
    rounded: "{rounded.control}"
    height: "28px"
    padding: "3px 10px"
  button-destructive:
    backgroundColor: "{colors.destructive-light}"
    textColor: "{colors.primary-foreground-light}"
    rounded: "{rounded.control}"
    height: "32px"
    padding: "4px 12px"
  input:
    backgroundColor: "{colors.card-light}"
    textColor: "{colors.foreground-light}"
    rounded: "{rounded.control}"
    typography: "{typography.body}"
    height: "32px"
    padding: "4px 9px"
  sidebar-item:
    rounded: "{rounded.control}"
    typography: "{typography.body}"
    height: "36px"
    padding: "0 10px"
  segmented:
    backgroundColor: "{colors.secondary-light}"
    rounded: "{rounded.selection-track}"
    height: "28px"
    padding: "3px"
  quota-window:
    textColor: "{colors.quota-normal-light}"
    typography: "{typography.quota-value}"
  model-share:
    textColor: "{colors.foreground-light}"
    rounded: "{rounded.cell}"
    typography: "{typography.detail}"
    height: "26px"
  source-badge:
    backgroundColor: "{colors.secondary-light}"
    textColor: "{colors.muted-light}"
    rounded: "{rounded.tag}"
    typography: "{typography.caption}"
    padding: "1px 6px"
  surface:
    backgroundColor: "{colors.card-light}"
    rounded: "{rounded.card}"
    padding: "{spacing.surface}"
  metric-value:
    typography: "{typography.usage-value}"
---

# Design System: Codex Quota

## Overview

**Creative North Star: "紧凑的桌面仪表盘"**

在 Codex Quota 的桌面主窗口里，开发者既能快速判断还剩多少额度，也能查到哪个模型或项目消耗最多。额度页把剩余比例和重置时间放在同一视线内。用量页先给出总数，再让人沿着趋势、模型和单条记录核对消耗。

侧栏和页头提供稳定的位置。最大的字留给读数。期间、单位和数据来源贴近对应数字。控件使用简短中文名称，Codex、Antigravity 和模型名保留原文。

**Key Characteristics:**

- 用量、明细、额度、设置四个入口共用一个桌面窗口。
- 跟随系统浅深色，以系统字体和等宽数字呈现密集数据。
- 颜色分别表达所选项、服务、额度状态和剩余时间。
- 未知、未定价、过期和真实零值各有对应的显示方式。

## Colors

按要回答的问题选色。下表的变量来自桌面主题。浅深值按列内的用途顺序排列。[主题样式](src/style.css)

| 用途 | 浅色 | 深色 | 组件与用法 |
| --- | --- | --- | --- |
| 当前选项、主要操作（`--primary`） | `#286fae` | `#3178b7` | 侧栏选中行、分段选项和保存按钮用蓝底白字。链接、键盘焦点和缓存命中率进度也用主色。 |
| 服务识别 | Codex `#3279bd`、Antigravity `#448d86` | 同浅色 | 用量趋势按服务堆叠，切换到单服务时仍用原色。两项服务的公开动态混排时，标签沿用图例色。 |
| 剩余额度（`--quota-*`） | `#63798c`、`#ae661f`、`#bd354b` | `#96adbf`、`#e5a05b`、`#e47786` | 正常用灰蓝，剩余大于 0% 且不超过 20% 用橙，耗尽用红。百分比和进度条同色，按实际读数判定。 |
| Codex 重置或到期倒计时（`--deadline-*`） | `#287448`、`#866a08`、`#b45214`、`#bd354b` | `#78c99a`、`#dfc55b`、`#efa063`、`#e47786` | 余时超过 24 小时用绿，6 小时 < 余时 ≤ 24 小时用黄，1 小时 < 余时 ≤ 6 小时用橙，1 小时以内用红。绝对日期和 Antigravity 的倒计时使用次要文字色。 |
| 与上期比较（`--usage-increase`、`--usage-decrease`） | `#bd354b`、`#287448` | `#e47786`、`#78c99a` | 消耗增加配红色和加号，减少配绿色和减号。持平用次要文字。上期为零时只给增减量。 |
| 每日 Tokens | `#a3d1ca` → `#679e94` → `#33786c` | 同浅色 | 热力图的青绿深浅表示数量。无用量和范围外日期均使用当前主题的 `--secondary`，仅范围内日期能打开明细。 |
| 未定价（`--unpriced`） | `#ab743e` | `#e5a05b` | 费用缺价时配「未定价」文字。读取失败的提示另用 `--warning-surface` 和 `--warning-text`。 |

中性色按层级使用。侧栏、页面、卡片在浅色中依次为冷灰、近白和白色，在深色中依次为近黑和两级深灰。正文用 `--foreground`，时间、单位、图例用次要文字色。表格分隔线用 `--border`，可输入边界用 `--input`。悬停用 `--accent`，选中用 `--primary`。

## Typography

界面沿用系统字体栈，macOS 优先系统字体，Windows 优先 Segoe UI 和 Microsoft YaHei。ECharts 使用 `system-ui, sans-serif`。模型名和短 ID 使用等宽字体。金额、百分比、时间与表格数值使用等宽数字，让刷新前后的位数容易对照。

| 用途 | 字号 / 字重 | 排版 |
| --- | --- | --- |
| 用量概览主读数 | 30px / 600 | 左对齐，行高 1.15。总 Tokens 带千位分隔符。 |
| 剩余额度 | 22px / 600 | 与窗口名称同一行，靠右。进度条紧随其下。 |
| 页标题、弹窗标题 | 18px、16px / 600 | 页标题置于固定页头。弹窗标题右侧为关闭按钮留位。 |
| 分项与明细行内汇总 | 14px / 600 | 主数值高于相邻的 12px 标签，金额和单位保持相邻。 |
| 正文、分组标题 | 13px / 400、600 | 设置标签和导航使用正文字号，分组标题通过字重区分。 |
| 表格、紧凑控件、倒计时 | 12px | 数值列右对齐。倒计时的数字用 600 字重，中文单位用常规字重。 |
| 辅助信息 | 10–11px | 用于短 ID、模型名、版本、图例和次行说明。 |

## Layout

主窗口默认 1140 × 760px，最小 860 × 560px。左侧栏初始宽 168px，可拖动分隔线或按左右方向键调至 300px。导航在顶部，用户选定的今日指标固定在底部。右侧页头高 56px，标题居左，页面级操作居右。[窗口配置](src-tauri/tauri.conf.json) · [窗口与导航](src/App.vue)

| 尺寸条件 | 布局变化 |
| --- | --- |
| 常规窗口 | 页面内边距 24px。概览区块间距 18px，三张汇总卡间距 12px，Tokens 卡最宽。额度和设置分组间距 16px。 |
| **窗口**宽 ≤ 960px | 页头水平内边距、内容内边距收至 18px。筛选项更紧凑。汇总表隐藏次要列。 |
| **概览内容区**宽 ≤ 780px | Tokens 卡独占首行，四项构成移到总量右侧。估算费用和缓存命中率并排在下一行。拖宽侧栏也能触发。 |
| **概览表格容器**宽 ≤ 800px | 模型表压缩水平内边距和数值列宽，保留 Tokens 与费用两列占比。 |
| **视口**宽 ≤ 820px | 额度窗口改为一列。这条样式断点低于桌面主窗口允许的最小宽度。 |

概览随页面纵向滚动，汇总表在 420px 高度内滚动。明细页让筛选、行内汇总和分页各占所需高度，把剩余空间交给表格。表头保持可见。长名称列可收窄，数字列保留可读宽度，空间不足时横向滚动。额度窗口通常两列并排，奇数个窗口的末项占满一行。

## Elevation & Depth

内容卡用一层细边框和底色划分区域。卡片底部的 Token 分项和费用口径用一层淡底衬托。常规按钮的 outline 样式和文本输入保留 `shadow-xs`，原生选择框保持平面。本机日志的范围提示使用细边框。多选和间隔编辑使用 `shadow-md` 浮层。对话框使用 `shadow-lg` 与黑色遮罩。深色浮层（`#27292e`）比卡片（`#202125`）略亮。

## Shapes

按钮、输入框和导航项采用 6px 圆角。分段选择器的轨道为 7px，内侧选中块为 5px，四周留 3px。卡片与对话框为 10px。占比横条末端为 2px，额度进度条为 3px。短条仍能分辨起止位置。

键盘焦点用 2px 内侧描边。普通控件用主色，主色选中项用白色。输入框同时改变边框色。聚焦前后保持相同的高度与间距，分段选项的焦点绘制在滑动高亮之上。

## Components

### 执行动作与选择范围

| 用途 | 控件 | 状态与尺寸 |
| --- | --- | --- |
| 保存、完成 | 默认按钮 | 主色底，常规高度 32px。紧凑操作行可用 28px。禁用时降低不透明度。 |
| 刷新、管理定价 | outline 按钮 | 工具栏使用 28px 小按钮和 14px 图标。刷新中显示进行中的动作，并暂时禁用入口。 |
| 返回图表、行内编辑 | ghost 按钮 | 默认透明，悬停显示底色。纯图标入口保留可访问名称。 |
| 清除历史 | destructive 按钮 | 确认弹窗写明所选服务和清除范围，最终确认使用危险色。 |
| 服务、期间和趋势指标 | 单选分段 | 原生 radio 负责键盘选择，蓝色选中块跟随选项。额度趋势的「24 小时」「7 天」等宽。 |
| 模型、日期时间、数值 | 原生选择框和输入框 | 工具栏为 28px，编辑字段为 32px。自定义期间有「开始」「结束」两个日期时间字段。错误文字紧贴字段组。 |
| 开关、依赖设置和多选 | Switch、Popover、Checkbox | 设置名在左，控件在右。子项以左细线和 16px 缩进关联主开关，停用时整组淡化。多选入口直接显示所选名称。空选显示「不显示」。 |

侧栏选中项高至少 36px，图标和文字相距 10px。普通行悬停出现底色，当前页使用主色底和半粗白字。设置与前三个数据入口间隔 12px。[滑动选择](src/components/SlidingSelection.vue) · [设置](src/components/SettingsPanel.vue)

### 查看用量与核对记录

- **用量卡。** 三项主读数为总 Tokens、估算费用和缓存命中率。Token 构成、上期范围、对话数与记录数放在各自卡片底部。已知零值直接显示，缺失计数用「—」，无定价的费用用「未定价」。明细页将同类指标收为行内汇总。
- **趋势与热力图。** 用量趋势高 210px，一次显示 Tokens 或费用。悬停读数列出两项指标并突出当前指标。未定价时段保留缺价信息。「今天」标出当前时刻，未来仅留时间轴。热力图至少铺满 53 周，始终按每日 Tokens 着色。点击有效时段进入逐条记录，「返回图表」恢复原来的范围。
- **占比。** 模型表将 Tokens 和费用占比并列放在各自的右对齐列。26px 高的单元格底条从左向右填充，主色以 29% 不透明度铺在等宽百分比后方。项目和对话则使用 4px 横条，数值在条外右侧。两者都按当前筛选的全部汇总项计算，真实零占比保留为 0.0%，分母为零或费用未知时显示「—」。
- **逐条明细。** 表头提供排序，表尾提供每页 20 / 50 / 100 条、翻页和页码跳转。可选列入口放在记录表旁。点记录时间打开费用拆分，金额列右对齐、合计在底部。分组详情中的二级弹窗只响应最上层的 Esc，关闭后焦点回到入口。

[用量与汇总表](src/components/UsagePanel.vue) · [逐条记录](src/components/UsageRecordTable.vue) · [分页](src/components/TablePagination.vue)

### 判断额度与读取状态

每项服务各有刷新入口、读取状态和上次成功时间。窗口名称和剩余百分比在第一行，6px 的进度条表示剩余量，下一行分别放相对时间和绝对重置日期。Codex 的「今日已用」紧跟窗口名称。趋势折线画已用比例，按采样时的状态分色，遇到采样中断就断开。超过七天只列绝对日期，七天内按余时显示天与小时、小时与分钟或分秒。重置倒计时归零时显示「等待实际重置」。

Antigravity 按来源返回的分组、模型与窗口排列。只报告一个窗口时占满可用列。未知额度显示「未知」，服务禁用的额度显示「未启用」。读取失败时保留上次成功的数值、时间，并提示过期。AIHOT 公开重置动态单列来源和适用服务。[Codex 额度](src/components/QuotaPanel.vue) · [Antigravity 额度](src/components/AntigravityPanel.vue)

菜单栏或托盘菜单将窗口名称、剩余比例和倒计时排在同一行，保留进度条。具体日期放在悬停提示和主面板。macOS 菜单栏标题使用系统等宽数字，服务图标与文字由系统共同居中。[系统入口](docs/usage.md)

### 浮层、键盘与动效

统计范围说明可通过悬停或聚焦打开。Popover 贴近触发控件，用于多选或少量字段编辑。涉及确认、定价或费用明细时使用 Dialog。费用明细最宽 760px，定价最宽 820px。长表与字段区自行滚动，底部操作保持可达。

侧栏和分段选择器的高亮滑动为 160ms ease-out。图表入场为 220ms，概览主读数与剩余额度的数字滚动为 240ms ease-out。表格、倒计时及辅助读数直接更新。关闭应用动画或启用系统减少动态效果时，直接呈现相应终态。[图表](src/components/Chart.vue) · [数字读数](src/components/AnimatedNumber.vue)

## Do's and Don'ts

- **Do** 让数字与其单位、时段和来源靠近。紧凑显示的计数提供查看完整值的入口。
- **Do** 使用当前主题和控件已有的尺寸、变体，保留原生选择、键盘操作与内侧焦点。
- **Do** 用文字、符号或图例与颜色共同表达服务、状态和变化。
- **Don't** 用 0% 或满格进度条填补未知额度，将缺失定价显示为免费，或将过期快照显示为刚刚读取。
- **Don't** 为解释布局重复写标题、提示或状态标签。保留能帮助用户选择、核对或处理错误的文字。
