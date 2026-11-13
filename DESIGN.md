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
  usage-increase-light: "#bd354b"
  usage-decrease-light: "#287448"
  chart-text-light: "#666b72"
  quota-normal-light: "#63798c"
  quota-warning-light: "#ae661f"
  quota-exhausted-light: "#bd354b"
  deadline-normal-light: "#287448"
  deadline-warning-light: "#866a08"
  deadline-urgent-light: "#b45214"
  deadline-critical-light: "#bd354b"
  warning-surface-light: "#fff7ec"
  warning-text-light: "#86531e"
  background-dark: "#18191c"
  foreground-dark: "#e9eaed"
  card-dark: "#202125"
  popover-dark: "#27292e"
  sidebar-dark: "#131417"
  primary-dark: "#3178b7"
  primary-foreground-dark: "#fff"
  secondary-dark: "#2a2c31"
  accent-dark: "#32353b"
  muted-dark: "#a3a7af"
  border-dark: "#34363d"
  input-dark: "#424650"
  destructive-dark: "#e47786"
  usage-increase-dark: "#e47786"
  usage-decrease-dark: "#78c99a"
  chart-text-dark: "#a3a7af"
  quota-normal-dark: "#96adbf"
  quota-warning-dark: "#e5a05b"
  quota-exhausted-dark: "#e47786"
  deadline-normal-dark: "#78c99a"
  deadline-warning-dark: "#dfc55b"
  deadline-urgent-dark: "#efa063"
  deadline-critical-dark: "#e47786"
  warning-surface-dark: "#2d2620"
  warning-text-dark: "#e5b983"
  chart-blue: "#3279bd"
  chart-teal: "#448d86"
  chart-amber: "#ad8044"
  chart-purple: "#9e6686"
  chart-grid: "#88888820"
  chart-calendar-label: "#888"
  heatmap-empty: "{colors.secondary-light}"
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
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "10px"
    fontWeight: 400
  small:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "11px"
    fontWeight: 400
  monospace:
    fontFamily: "ui-monospace, SFMono-Regular, Consolas, monospace"
    fontSize: "11px"
    fontWeight: 400
  detail:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "12px"
    fontWeight: 400
  control:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "13px"
    fontWeight: 400
  dialog-title:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "16px"
    fontWeight: 600
  page-title:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "18px"
    fontWeight: 600
  compact-value:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "13px"
    fontWeight: 600
  responsive-value:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "23px"
    fontWeight: 600
  quota-value:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
    fontSize: "24px"
    fontWeight: 600
  usage-value:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', sans-serif"
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
  button-primary:
    backgroundColor: "{colors.primary-light}"
    textColor: "{colors.primary-foreground-light}"
    rounded: "{rounded.control}"
    padding: "4px 12px"
    height: "32px"
  button-outline:
    backgroundColor: "{colors.background-light}"
    textColor: "{colors.foreground-light}"
    rounded: "{rounded.control}"
    padding: "3px 10px"
    height: "28px"
  button-ghost:
    rounded: "{rounded.control}"
    padding: "3px 10px"
    height: "28px"
  button-destructive:
    backgroundColor: "{colors.destructive-light}"
    textColor: "{colors.primary-foreground-light}"
    rounded: "{rounded.control}"
    padding: "4px 12px"
    height: "32px"
  input:
    rounded: "{rounded.control}"
    typography: "{typography.control}"
    padding: "4px 9px"
    height: "32px"
  segmented:
    rounded: "{rounded.selection-track}"
    padding: "3px"
    height: "28px"
  source-tooltip:
    rounded: "{rounded.control}"
    typography: "{typography.detail}"
    padding: "10px 12px"
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

**Creative North Star: "克制、清晰、紧凑的跨平台桌面仪表盘"**

沿用现有桌面工具的视觉秩序：稳定的侧栏、紧凑的数字、清晰的表格和图表。主界面由 Tauri WebView 内的 Vue 3、shadcn-vue 与 Apache ECharts 实现，采用用量、明细、额度、设置四个入口。以系统字体、明确分组和原生控件支持查看额度与比较用量，不引入装饰性品牌重设计。

实际样式源为 `src/style.css`，交互源为 `src/App.vue` 与 `src/components/`。`src/components/ui/` 由 shadcn-vue CLI 生成；使用其 size、variant 接口和主题变量，覆盖放在调用层或样式源中，不手改生成组件。图标采用当前官方 `@lucide/vue` 包，统一线性图标。

**Key Characteristics:**

- 四入口侧栏与紧凑桌面布局。
- 跟随系统浅深色，使用系统字体与等宽数字。
- Tokens 与费用并列展示，保留缺失、未定价与估算标识。
- 简短中文控件名称、原生键盘行为与内侧焦点。

## Colors

界面跟随操作系统浅深色。深色主题以近黑的侧栏和主背景承托逐层提亮的卡片、浮层，降低大面积灰感并保留文字对比度。背景、内容表面、侧栏、边框、主文字和次要文字分别使用语义变量。蓝色用于选中导航、单选项与提交动作；额度的正常、预警、耗尽状态独立使用灰蓝、橙和红，并保留实际数字。颜色不能把未知数据伪装为正常。

图表按需引入 ECharts 模块。热力图用低至高的青绿色量阶表示每日 Tokens 用量，费用与未定价记录保留在悬停提示中；金额缺失不显示为零。系统字体和图表字体遵循系统外观，不加载远程字体。

热力图保持至少 53 周的全年网格，较早的所选历史会扩展网格。所有日期都保留格子，所选时间范围外及范围内无记录日期使用主题的 secondary 灰色，格子之间以卡片底色分隔；有用量的日期使用青绿色量阶。范围外的格子仅作为日历背景，不计为零用量，也不响应明细跳转；所选范围内的日期保留悬停与点击明细。已扫描但所选范围无记录时仍显示灰色网格。

用量同期比较的 `usage-increase-*` 为红色，配合加号；`usage-decrease-*` 为绿色，配合减号；持平使用中性色。它们与额度状态、倒计时紧迫程度分别命名，不能交换语义。组件 token 中的颜色引用记录浅色默认值，实际组件通过同名 CSS 语义变量跟随深色主题；派生色阶仅供设计面板参考，不替换产品配色。

额度重置与重置卡到期倒计时使用独立的 `--deadline-*` 时间状态色：剩余时间超过 24 小时为绿，超过 6 小时至 24 小时为黄，超过 1 小时至 6 小时为橙，1 小时以内为红。仅倒计时文字着色，保留具体时长与中性色绝对日期；额度窗口的倒计时与日期分列两端，重置卡的剩余时长和日期整体靠右；未知时间不着状态色。每张尚未到期且在七天内到期的重置卡都显示倒计时，数量仍以接口快照为准。缓存命中率进度条通过 `--quota-color` 使用主题主色，与额度状态色分开。

## Typography

主界面沿用 `src/style.css` 中的系统字体栈，图表使用 `system-ui, sans-serif`；不引入独立展示字体。短 ID 与模型名使用等宽字体，只有数值采用等宽数字特性。

基础字号 13px，表格与辅助信息 12px，页标题 18px。概览将 Tokens 与费用作为 25px 主指标，同排的四项 Token 构成使用 18px；对话数、缓存命中率与同期范围放在下方的 12px 辅助行。明细页使用 13px 行内汇总，保留表格的空间。用量与明细页顶部的总 Tokens 和模型、对话、项目汇总表的 Tokens 均显示带千位分隔符的完整数字；逐条明细的输入、输出、缓存等 Token 列保留简写，悬停显示完整值。额度值 24px。较小字号只用于短 ID、图例和版本。数据、金额、百分比、时间使用 tabular-nums；模型与短 ID 使用等宽字体。正文、按钮和导航不使用技术装饰字体。

## Layout

切换侧栏菜单后，页面主内容与用量明细表的横纵滚动位置均回到起点。明细页在表格上方以“按记录 / 按对话 / 按项目”切换逐条记录或汇总，共用日期范围、模型、自定义日期和表格排序指标。切换视图清空搜索词，表格横纵滚动回到起点；切换侧栏页面和重启后恢复当前视图及筛选、搜索状态。沿用原对话页的存储键和筛选偏好；相对日期范围按当前日期重新计算。偏好通过现有 VueUse 的 `useLocalStorage` 保存，读取入口统一校验，页面内使用类型化状态；已选模型暂无记录时保留选项并显示空结果。用量概览在会话内保持独立的临时筛选与分组状态，并可从项目或对话汇总一键将当前日期、模型与排序指标同步跳转至明细页。

主窗口初始为 1140×760px，最小为 860×560px，沿用旧版桌面比例。初始侧栏 168px，可通过分隔线拖动或方向键调至 168–300px；导航从顶部开始，不重复窗口中的产品名。页面标题区高 56px，内容边距 24px，960px 以下收为 18px。侧栏今日指标固定底部。

Antigravity 按接口分组展示额度。所有分组都只有一项额度时，分组在宽窗口中两列并排，820px 及以下改为上下排列；存在多额度组时，各组保持上下排列，组内额度沿用两列布局。单组或组内单项占满对应网格的可用宽度，不保留空列。

额度窗口按实际返回的数据排列；单窗口或奇数窗口的末项占满整行，不为未返回的五小时等窗口保留空列。

筛选与日志来源间隔 8px，概览主要内容间隔 18px。Tokens、费用和四项 Token 构成位于同一横排的单层边框内，各格内边距 14px，主指标优先留足完整数字宽度；1100px 以下主指标占第一行、四项构成占第二行，辅助信息紧随其后。用量趋势绘图区高 210px，额度趋势每个绘图区高 120px；趋势后接同一区域内按模型 / 项目 / 对话切换的完整汇总表（最大滚动高度 420px），对话维度直接按表头查看高消耗排序，不再另设前五项卡片。概览页纵向滚动；明细页的筛选、汇总和表格标题行不参与高度压缩，表格内容区填满剩余高度并独立滚动，按对话 / 按项目切换不改变外框和控件位置。960px 以下隐藏表格次要目录/时间列，完整值保留悬停入口；详情表格可横向滚动，表头分隔线支持拖动和左右方向键调整列宽。汇总表按列职责分宽：记录数 80px、占比 100px，费用 120px，缓存命中率 104px，最近用量 140px；Tokens 按当前汇总数字的最大位数留足宽度，至少容纳 14 个等宽字符及单元格内边距。项目名列为 144px，目录承接剩余空间且至少为 208px；隐藏目录的窄窗口中，项目名重新承接剩余空间。对话、模型名称列保留弹性，空间不足时允许横向滚动。定价表的数值和操作列按内容收紧，模型列承接剩余空间。明细表初始由模型列吸收剩余宽度，拖拽或键盘调宽时固定实际列宽，避免再次均摊。详情的总量、完整会话 ID、可展开的工作目录与主仓库映射位于表格上方；多档位时显示分档汇总，单档位不占用额外区域。ID 与路径可选择复制。

## Elevation & Depth

页面和卡片主要通过背景明度、单层细边框与间距区分层级。普通 outline 按钮和文本输入保留组件库的微弱 `shadow-xs`；NativeSelect 在主题层去掉阴影。Popover 使用 `shadow-md`，Dialog 使用 `shadow-lg` 与背景遮罩。本机日志 Tooltip 使用细边框而不加阴影。阴影值从锁定的 Tailwind 主题提取至配套索引，焦点使用内侧 ring 或描边，不作为浮起效果。

## Shapes

控件与导航使用轻微圆角，选中滑块的圆角略小于背景轨道；卡片和 Dialog 使用更柔和的圆角。进度条和热力图单元格保留较小圆角。具体值由 `rounded` token 给出；沿用一层容器边框，滑动高亮通过裁剪区域跟随实际选项尺寸。

## Components

### 操作与输入

普通操作使用 shadcn-vue `Button` 的 outline、ghost 和 sm；小按钮、下拉框、日期、分段选择器与搜索框统一为 28px，文字 12px，小按钮图标 14px。保存、完成使用默认强调样式，清除确认使用 destructive；默认按钮与文本、数字编辑框为 32px，文字 13px。优先复用组件库及其 size、variant、主题接口；尺寸与必要的主题适配集中在应用样式层，不修改生成组件，不以手写 CSS 重造控件。聚焦使用边框变色与 2px 内侧 ring / 描边，不改变控件外轮廓和高度；滑动高亮上方保留可见的内侧焦点标识。

服务图标筛选、日期范围、汇总分组、趋势指标、明细分组和额度趋势范围使用原生 radio 加滑动选中背景，支持 Tab 与方向键；额度趋势的 24 小时与 7 天选项等宽。模型、刷新间隔和提醒时间单位使用 shadcn-vue `NativeSelect` 与 `NativeSelectOption`，沿用组件的原生选择行为、箭头和状态管理；主题层统一尺寸并去掉控件阴影。提醒时间单位与相邻数字输入框保持 32px 高，其余选择框为 28px。自定义日期使用原生 date 输入；自定义刷新间隔使用带原生 number 输入的 Popover，最小 30 秒，保存生效，取消和 Esc 放弃。

按钮与输入沿用组件库的 hover、disabled、invalid 状态；禁用时降低不透明度并阻止操作。导航和分段选项悬停改变文字或背景，选中态使用主色底与白色文字；原生 radio 保留 Tab 与方向键，实际控件上方绘制内侧焦点。

### 设置与弹窗

设置分组内边距 16px，设置行最小高度 32px，相邻行间隔 8px，保持左侧标签、右侧控件。额度监测标题与主开关共用一行，其依赖设置缩进 12px。开关只通过点击控件本体或聚焦后的键盘操作切换，左侧文字不触发切换；通过 aria-labelledby 保留可访问名称。额度监测关闭时，依赖设置一起禁用和淡化，菜单栏/托盘、登录启动与用量扫描保持独立。多选指标和列选项采用 Popover + Checkbox + Button，按钮按选项顺序直接显示已选名称，空选显示“不显示”，连续选择立即保存。对话明细、价格编辑与清除确认使用 Dialog，保留标题、说明和完成/取消动作。定价弹窗按服务与模型范围筛选，含未定价记录和有用量的模型优先显示；标准单价、速度倍率和长上下文通过 fieldset 分组，底部操作固定在滚动内容之外。已有模型名称只读，编辑态 Esc 返回列表并恢复焦点；列表显示更新错误、官方来源与快照日期。

### 数据、图表与提示

本机扫描时间由页头刷新按钮以相对时间显示，悬停提供准确时间；当前生效的统计起止日期与来源在筛选下方显示，来源旁的帮助按钮使用 ghost / icon-xs、CircleHelp 与 help 光标，复用 Reka Tooltip 在悬停或键盘聚焦时展示统计范围，移出、失焦或 Esc 关闭；警告放在汇总前。API 等价费用不代表订阅账单；汇总沿用统一“估算费用”标签并累加已定价记录，全无定价显示“未定价”；费用占比基于已定价金额。单条详情保留 `--unpriced` 未定价状态；分组表保留缓存命中率，明细搜索同步更新顶部行内汇总与占比基数。旧历史 Standard 未明确报告档位时显示“估算”，费用悬停保留未舍入值。定价列表由后端合并目录与日志模型，未知模型直接显示未定价。前端只聚合 Rust 返回的十进制费用字符串，不重新实现定价规则。同期比较仅在概览显示；当前未结束的时间范围按本地时刻对齐上期。

额度卡各自提供刷新按钮、读取状态和精确到秒的成功读取时间；切换进入页面仍刷新已启用服务，读取失败保留已有读数及时间并标为过期。倒计时本地计算，归零显示等待实际重置。额度折线按后端 segment 分段，重置或观测中断处不连线，实测点始终可见；颜色由历史已用百分比决定，不足 80% 为灰蓝，80% 至不足 100% 为橙，耗尽为红，不随当前读数整体变色。悬停在图表标题行显示时间与读数，横向 12px 内没有采样则显示“无采样”。公开重置动态与个人额度分开，最多展示最近三条，展示适用范围，预告与 AIHOT 估计分别标注；链接经 Rust 检查后打开。重置卡本地到期后显示“已到期”，数量保持接口值。原生菜单在额度行下显示重置日期与本地倒计时，并按到期时间逐张列出重置卡；使用系统菜单文字样式，倒计时原位更新，不重建菜单。

同期对比在 Tokens 与费用卡片内分别以“增减量（百分比）”展示，每项只在增减量前保留一个正负号；增加用红色与加号，减少用绿色与减号，持平保持中性色；上期为零时仅显示增加量，上期数值放在悬停提示中。用量趋势通过「Tokens / 费用」切换单一指标，以 Codex 蓝色、Antigravity 绿色分色堆叠柱形，保留服务图例与轴单位，单服务筛选保持对应颜色；完全未定价的服务时段不画费用值，部分缺价显示未定价数量，全部缺价显示明确空态。图表指标与表格排序互不改变。汇总表保留 Tokens 与费用两列，长排序表头在既有列宽内自然换行，通过表头选择升降序及字段，占比明确标记 Tokens 或费用，沿用最近选择的消耗指标。热力图颜色深浅固定表示每日 Tokens 用量，趋势与热力图的提示同时显示 Tokens、费用和未定价记录数，时间轴沿用现有展示方式。通知设置区分持续、临时横幅、未开启桌面提醒和无法确认的样式；首次授权后的持久通知引导与手动入口共用 Dialog，自动引导按已显示记录去重，与版本说明依次展示。

更新说明共用 Markdown 组件，正文 12px、标题 14px，保留标题、列表、链接与原生折叠说明，HTML 注释隐藏；设置页超过 220px 滚动，版本首次打开使用独立 Dialog，关闭后按版本记录。HTML 经统一清理后仅保留排版标签与必要属性，不加载图片或执行脚本。

汇总表与逐条记录使用同一分页条：shadcn-vue Pagination 负责总页数、上一页 / 下一页及首尾页禁用状态，组合 NativeSelect 选择每页条数（20 / 50 / 100）和 Input 输入页码跳转，保留总条数。控件统一 28px，继承主题内侧焦点；页码输入与总页数保持 8px 间距并作为一组不换行。分页条位于滚动区外，表头与页脚保持可见。筛选或排序改变回第一页，定期刷新保留仍有效的页码，统计总量不受分页影响。明细页保存排序字段和方向；每页条数按汇总、逐条两类保存。缺失值在两个排序方向均置后。逐条表格旁直接提供“可选列”入口，复用设置中的名称列表与保存逻辑，Esc 只关闭列菜单。

全局逐条记录与分组详情复用 `UsageRecordTable`，共享时间、模型、Token、费用和可选列的显示、排序、分页与列宽；表格显示服务名，全局表额外显示会话标题和项目，在表格标题栏直接设置可选列。Codex 会话标题优先使用本地元数据，缺失时保留项目名与短 ID；已有标题的分组行在次行展示项目与短 ID，悬停可查看完整显示标题与 ID。

用量趋势的日 / 小时柱和当前筛选内的热力图日期可进入全局逐条记录，沿用服务与模型筛选，清空搜索，并将所点时段与原统计范围取交集。时间控件保留自动带入的秒及毫秒边界，来源行显示实际范围；右侧使用 ghost / sm“返回图表”按钮。返回按钮与侧栏“用量”共用恢复逻辑，恢复原服务、模型、时间和图表筛选，明细筛选不覆盖返回状态。

记录时间使用可聚焦的文字按钮打开费用详情。费用弹窗宽度由全局弹窗主题规则控制，最多 760px，内容区可滚动；四列分别为用量、Tokens、每百万 Tokens 单价及费用，金额右对齐，底部展示后端合计。计价模型、档位、倍率和长上下文条件仅显示实际有据的数据；未定价、未报告与零值分开。弹窗可从分组明细内打开，Esc 仅关闭最上层弹窗并返回原入口。详情通过 `usage_cost_detail` 按需读取，加载与失败反馈位于费用区，失败可重试；前端不重算单条价格。

### 动效与可访问性

侧栏和分段选择器共用 `SlidingSelection`，选中块采用 160ms ease-out 过渡；白色文字与加粗仅在滑块覆盖范围内显示，未覆盖处保留普通文字。高亮副本只包含展示元素，使用 aria-hidden、inert 和 pointer-events 隔离，实际按钮和原生 radio 保留唯一的键盘与表单行为。尺寸变化时按实际选项位置更新裁剪区域。

图表动画 220ms。应用动画开关和系统减少动态效果均能关闭动画，滑块直接显示在新选中项上。系统浅深色变化会重新应用 ECharts 主题，图表容器通过 ResizeObserver 调整尺寸并在卸载时释放。

原生表单控件保留标签、键盘行为及焦点样式。图标动作保留名称；图表具有文字辅助说明和对应汇总数字。页面支持平台常用刷新与设置快捷键，原生菜单事件与页面动作共用业务命令。macOS 菜单栏使用系统菜单栏字号的等宽数字字体，图标沿用 tray-icon 的 18pt 逻辑高度与完整图像对齐区域，不将 alignmentRect 缩小到字体 cap height，以免较矮菜单栏裁切图标；图标与文字由系统作为一个整体布局。

## Do's and Don'ts

### Do

- **Do** 复用组件的 size、variant 和主题变量，保留表单标签、键盘操作与可见内侧焦点。
- **Do** 让数值、单位、正负号与状态色共同表达信息；保留完整值的查看入口。
- **Do** 让明细筛选和标题行保持自身高度，仅由表格内容区承担剩余高度与滚动。
- **Do** 区分缺失、未定价、真实零值与估算，保留数据来源及过期状态。

### Don't

- **Don't** 手改生成组件或生成索引；修改源头后重新生成。
- **Don't** 用负边距、固定偏移或外扩焦点掩盖布局问题。
- **Don't** 添加重复解释布局的文案、无关装饰或未经确认的展示字体。
- **Don't** 把离线示例、源码支持或编译通过写成真实服务与系统交互验收通过。

### 依据与验收边界

迁移依据为 Git 历史中的 Swift 源码、README、PRODUCT 和旧版额度/设置截图。历史截图不作为当前交互依据。`?preview` 使用明确标注的匿名离线示例，仅用于界面验收；普通浏览器环境不会尝试读取本机凭据或伪造服务成功。

本次记录以当前源码、组件 variant 和锁定的 Tailwind 主题为准。前一轮类型检查、前端构建、Rust 编译检查及已有 Swift 检查通过；Chrome 控制入口受工具限制，系统菜单栏未取得可判断的截图，因此新增界面状态与原生对齐尚未完成视觉验收，Windows 也未进行实机检查。

文档结构遵循 [DESIGN.md 格式](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md)。配套 `.impeccable/design.json` 仅保存色彩元数据、阴影、动效、断点、组件展示片段和本文叙述，基础 token 以本文件为准。

合并验收：前端构建与 Rust 编译检查通过；Chrome 离线预览检查双服务筛选和分页、Codex 标题、两项服务的代表费用记录及缺失值、嵌套弹窗键盘焦点、额度刷新与更新时间。保留远端既有的汇总费用展示方式。未连接真实服务或验收原生托盘。
