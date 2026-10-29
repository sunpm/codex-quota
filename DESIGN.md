---
name: Codex Quota
description: 克制、清晰、紧凑的原生 macOS 额度与用量仪表盘。
colors:
  quota-normal-light: "#6C6C70"
  quota-normal-dark: "#98989D"
  quota-warning-light: "#C75300"
  quota-warning-dark: "#FFA15F"
  quota-exhausted-light: "#D1243A"
  quota-exhausted-dark: "#FF7A90"
typography:
  page-title:
    fontFamily: "system-ui"
    fontSize: "18px"
    fontWeight: 600
  usage-value:
    fontFamily: "system-ui"
    fontSize: "25px"
    fontWeight: 600
    fontFeature: '"tnum"'
  quota-value:
    fontFamily: "system-ui"
    fontSize: "24px"
    fontWeight: 600
    fontFeature: '"tnum"'
  control:
    fontFamily: "system-ui"
    fontSize: "13px"
    fontWeight: 400
  detail:
    fontFamily: "system-ui"
    fontSize: "12px"
    fontWeight: 400
rounded:
  heatmap-cell: "2px"
  navigation: "6px"
  tooltip: "8px"
  card: "10px"
  sidebar-glass: "16px"
spacing:
  tight: "4px"
  label: "6px"
  related: "8px"
  compact: "12px"
  metric: "14px"
  section: "16px"
  analysis: "18px"
  page: "24px"
components:
  panel-card:
    rounded: "{rounded.card}"
  sidebar-item:
    rounded: "{rounded.navigation}"
    typography: "{typography.control}"
    padding: "0px 10px"
  metric-card:
    rounded: "{rounded.card}"
    padding: "{spacing.metric}"
  quota-window-progress:
    height: "6px"
  chart-tooltip:
    rounded: "{rounded.tooltip}"
    padding: "{spacing.compact}"
    typography: "{typography.detail}"
---

# Design System: Codex Quota

## Overview

**Creative North Star: "原生仪表盘"**

克制、清晰、紧凑。界面帮助用户查看额度、比较用量，以稳定的数字、明确的分组和系统控件建立秩序。识别来自 Codex 标识与细节的一致性；正文、数据和操作优先于装饰。

这是原生 macOS 视觉规范，最低系统版本为 macOS 13。保留 SwiftUI / AppKit 的字体、控件、焦点、菜单和窗口惯例；macOS 26 及以上的部分控件使用系统 Liquid Glass。使用简体中文，保留服务名、模型名、Tokens、USD 等必要标识。产品约束见 [PRODUCT.md](PRODUCT.md)，实现与协作约束见 [AGENTS.md](AGENTS.md)。

**Key Characteristics:**

- 系统字体与语义颜色适应系统外观，额度状态使用独立的语义色。
- 用底色、细边框、留白和对齐表达层次，操作使用原生控件。
- 数值便于比较；来源、时间、单位、未知和过期状态贴近对应数据。
- 文案具体简短，保留表单标签与必要口径，删除重复解释布局的说明。

记录基于 2026-10-29 工作区源码、[额度预览](docs/images/quota.png)、[设置预览](docs/images/settings.png)及本次会话中主窗口的现场观察。预览为示例数据，只用于核对对应页面；无窗口装饰的离线图片不能证明系统材质、焦点或禁用态的最终外观。当前窗口的用量列表与详情往返已观察；精确最小窗口、深色外观及 VoiceOver 未完成现场验收，不将源码支持写成验收通过。

格式遵循 [DESIGN.md 规范](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md)。文件头仅收录已实现的固定值：为兼容格式，尺寸以 `px` 保存，数值对应 SwiftUI 的逻辑点；原生实现仍使用 point，不进行 CSS 物理单位换算。`system-ui` 对应原生系统字体，`tnum` 对应 `.monospacedDigit()`。系统色、材质和语义字级没有固定值，按下文的原生 API 使用。工具暂未识别 `macos` 平台，不因此将产品改记为 Web 或 iOS。

## Colors

以系统中性色承载内容，强调色标识操作与选中状态，额度灰／预警橙／耗尽红传达额度状态。颜色按用途命名。

### Primary

- **系统强调色**：`Color.accentColor`，用于导航、分段控件的实色选中底及更新标记；选中项的文字与图标使用白色。原生突出按钮和链接遵循系统样式。不要从截图提取一个蓝色常量代替它。
- **额度状态色**：统一调用 `quotaColor(remaining:)`，定义位于 [QuotaAppearance.swift](Sources/CodexQuota/QuotaAppearance.swift)。`quota-normal-*` 为额度灰，`quota-warning-*` 为预警橙，`quota-exhausted-*` 为耗尽红；文件头的 `light` / `dark` 成对使用。

| 实际剩余值 | 色彩角色 | 当前应用 |
| --- | --- | --- |
| 未知 | 系统 `.secondary` | 不推测正常或耗尽 |
| 小于等于 0 | 耗尽红 | 百分比与额度进度 |
| 大于 0、小于 20 | 预警橙 | 百分比、进度及需要关注的提示 |
| 大于等于 20 | 额度灰 | 百分比与额度进度 |

额度页的错误正文使用主文字色，图标使用预警橙；用量读取警告与未定价提示使用预警橙。定价编辑器的校验错误当前直接使用系统 `.red`，这是表单错误样式，不作为额度色的新入口。

### Secondary

图表分类使用 SwiftUI 系统色，不与额度阈值共用含义：趋势与输入为 `.blue`，输出为 `.purple`，缓存读取为 `.teal`，缓存写入为 `.orange`。分类始终配文字或数值，颜色不独自承担识别。热力图使用 `.teal` 的透明度层级；它表达用量强弱，不表达额度健康度。

### Neutral

| 原生语义 | 用途 |
| --- | --- |
| `NSColor.windowBackgroundColor` | 主窗口内容背景、旧系统侧栏 |
| `NSColor.controlBackgroundColor` | 共享卡片背景 |
| `.primary` / `.secondary` / `.tertiary` | 正文、辅助信息、弱化装饰 |
| `.primary.opacity(0.07)` | 卡片细边框 |
| `.secondary.opacity(0.18)` | 额度进度轨道 |
| `.regularMaterial` | 图表悬停浮层 |

Codex 服务小标识为白底、黑色模板图案；菜单栏图像设置 `isTemplate = true`，由系统处理明暗与高亮。两者都不能替代额度状态色。

**The 状态归属 Rule.** 额度颜色只由真实剩余值决定；品牌色、图表类别和显示舍入不改变它。

## Typography

全界面使用系统字体，不引入自定义展示字体。数值使用等宽数字，正文保持正常字宽。系统 `.headline`、`.body`、`.callout`、`.title2`、`.title3` 保留语义字级，不从截图反推固定字号或行高。

| 角色 | 取值或入口 | 应用 |
| --- | --- | --- |
| 页面标题 | `page-title` | 主窗口标题栏下的页面名称 |
| 用量主数字 | `usage-value` | 概览的总 Tokens 与 API 等价费用 |
| 额度主数字 | `quota-value` | 每个额度窗口的剩余百分比 |
| 操作与导航 | `control` | 侧栏和设置；选中导航使用 semibold |
| 时间、说明、明细 | `PanelTypography.detail` / `detail` | 统一可读的辅助字级 |
| 恢复倒计时 | 系统字体 13pt、medium | 与主数字相邻，使用等宽数字 |
| 分组标题 | `.headline` | 卡片、图表与表单分组 |

金额、百分比、倒计时、时间和表格数字使用 `.monospacedDigit()`。表格数值靠右对齐；名称靠左。长名称与路径通常单行截断并提供 `.help`；对话详情中的完整 ID 与工作目录允许选择复制。

**The 可比较数字 Rule.** 同列数值保持相同字级、对齐和单位口径；缩写不移除完整值的查看入口。

## Layout

使用固定侧栏与可伸缩内容区。主窗口初始内容尺寸为 1140 × 760pt，最低内容尺寸为 860 × 560pt；数值来自 [ControlPanelController.swift](Sources/CodexQuota/ControlPanelController.swift)，是实现约束，并非最小尺寸验收记录。

| 空间角色 | 现有规则 |
| --- | --- |
| 侧栏 | 宽 188pt，内部 padding 12pt；macOS 26 玻璃外再留 8pt |
| 页面栏 | 高 56pt，左右 padding 使用 `page`，标题与刷新操作分列 |
| 内容外边距 | `page` |
| 额度与设置 | 内容最大宽 760pt，居中 |
| 用量内容 | 概览主体纵向滚动；对话与项目的筛选、汇总保持在表格上方，表格填满窗口剩余高度并自行滚动 |
| 卡片内边距 | 设置与额度常用 `section`，分析常用 `analysis`，概览指标用 `metric` |
| 密切关联信息 | 使用 `tight`、`label`、`related`，不强制整理为单一倍数网格 |

共享 `panelCard()` 只负责表面，不内置 padding；调用点决定密度。相邻组件先复用既有值，避免为单个位置建立新的全局 token。

分析内容通过 `ViewThatFits(in: .horizontal)` 在横向并列与纵向堆叠间选择；两个并列区域分别保留至少 290pt。热力图保留水平滚动。没有 Web 式设备断点，不将窗口最小宽度登记为 CSS breakpoint。

汇总表使用原生 `Table`，列宽上下限如下；长名称不能独自决定整表宽度。首要比较字段为名称、Tokens、API 等价费用。下表记录当前实现，不代替窄窗口检查。

| 列 | 最小 / 理想 / 最大宽度（pt） |
| --- | --- |
| 名称 | 130 / 170 / 260 |
| Tokens | 70 / 80 / 140 |
| API 等价费用 | 100 / 105 / 180 |
| 占比 | 60 / 65 / 100 |
| 缓存命中率 | 80 / 85 / 110 |

页面当前排布以 [MainView.swift](Sources/CodexQuota/MainView.swift) 与 [UsageView.swift](Sources/CodexQuota/UsageView.swift) 为准，不把某一页的卡片数量提升为所有页面的规则。

## Elevation & Depth

主要依靠系统底色、细边框、分隔线与留白分组。源码没有自定义阴影层级；原生控件和 sheet 的系统效果继续由平台管理，不声明“全应用没有阴影”。导航与分段选择器各保留一个选中背景，匹配目标选项的位置与大小，使用 0.16 秒 ease-out 滑动。滑块覆盖区域显示白色 semibold 标签，外部显示主文字色 regular 标签；两层使用互补遮罩，避免文字提前变白、变粗或叠出重影。开启系统“减少动态效果”时直接切换；数据与页面内容不随选中背景做整体动画。

普通操作按钮统一使用 `.bordered`。macOS 26 及以上侧栏使用 `glassEffect`，突出操作按钮使用 `.glassProminent`；旧系统侧栏使用窗口背景与分隔线，突出操作按钮使用 `.borderedProminent`。开关保留系统外观。图表浮层使用 `.regularMaterial` 和主文字色 10% 透明度的细边框，不添加自行绘制的模糊或阴影。

**The 系统材质 Rule.** 材质与控件状态交给平台；用自定义表面时，复用 `panelCard()` 的底色和边框。

## Shapes

圆角按角色区分：卡片使用 `card`，导航选中底与 Codex 小标识使用 `navigation`，图表浮层使用 `tooltip`，新系统侧栏玻璃使用 `sidebar-glass`，热力单元使用 `heatmap-cell`。分段选择器轨道圆角为 8pt，选中底为 6pt；原生按钮、输入框与开关的外形由系统样式决定，不强加卡片圆角。

额度条和 Token 拆分条使用 `Capsule`。额度组件默认高度为 7pt，额度页显式使用 `quota-window-progress`；拆分条高 8pt。卡片描边为 1pt；Codex 小标识的黑色 12% 透明度描边为 0.5pt。图标优先使用 SF Symbols，服务标识使用已授权的 [codex.svg](Resources/codex.svg)，来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## Components

### Buttons

使用 [PanelButtonStyle](Sources/CodexQuota/QuotaAppearance.swift)，普通按钮使用标准原生样式，仅 prominent 样式按系统版本分派。保存、下载和已安装更新说明的完成操作可使用突出样式；链接使用 `.link`，导航与列表内入口使用 `.plain`。不自绘 hover、focus 或按下背景来覆盖原生控件。

默认操作与取消操作使用对应 `keyboardShortcut`；禁用通过 `.disabled` 表达，刷新或提交中的等待通过 `ProgressView` 或动作名称体现。保留必要的按钮名称；纯图标必须有可理解的辅助标签。

### Cards / Containers

`panelCard()` 位于 [UsageView.swift](Sources/CodexQuota/UsageView.swift)，使用控制背景、`card` 圆角和细边框。图表、设置组、额度块及指标卡复用这一表面；字号与 padding 由内容角色决定。标题、数值和操作通过对齐建立层级，不额外加解释布局的副标题。

### Inputs / Fields

额度刷新间隔行只显示“刷新间隔”和当前时长按钮（默认“5 分钟”）；点击时长直接在原位置编辑秒数，单位紧邻输入框，不经过菜单或弹层。回车或点击输入框外保存、失焦并恢复时长显示；低于 30 秒按 30 秒保存，无法解析为整数时保留原值。数值使用等宽数字，输入框保留最少 30 秒的辅助标签及悬停提示，不在主设置行重复约束说明。

定价搜索与编辑使用 `.roundedBorder` 的 `TextField`；表单保留字段标签，错误就近显示。时间、指标与分组筛选复用 `PanelSegmentedPicker`，以 SwiftUI 按钮和 `matchedGeometryEffect` 实现滑动选中背景；选中底使用系统强调色实色，文字为白色，不另加边框。`PanelSelectionIndicator` 与 `PanelSelectionLabel` 共用背景和文字遮罩的几何动画。保留控件名称、选中语义、焦点与左右方向键切换。点击或重新点击“自定义”打开原生 popover，其中的 `DatePicker` 保留开始、结束标签及日期先后约束，修改立即生效；点击“完成”或浮层外部关闭。日期范围显示在已有说明行内，展开与关闭浮层不改变筛选区域高度。布尔设置使用 `.switch` 与 `.small`，可见行标签和隐藏控件标签表达同一设置。

### Navigation

五个现有入口为概览、对话、项目、额度、设置；设置位于额度下方，顶部额外留 12pt 区分主导航与设置。图标槽为 22 × 22pt，图文间距为 `related`，每行最小高度 34pt。选中行使用系统强调色实色背景、白色文字与图标，文字为 semibold，并设置 `.isSelected`；未选中行保持主文字色。设置入口的更新标记在选中时也使用白色。侧栏自定义为按钮列表，不宣称它具备尚未验证的原生列表键盘行为。

软件更新卡片展示版本、检查操作和更新结果；“自动检查更新”放在下方设置分组的“登录 Mac 时启动”之后，沿用左侧标签、右侧开关的行布局。设置底部不重复应用名称或致谢链接；第三方来源与许可保留在文档及随包文件中。

### Tables / Details

汇总表使用 `.inset(alternatesRowBackgrounds: true)`，数值靠右、等宽数字，费用允许两行。对话与项目表格填满可用高度，不嵌套在页面级 `ScrollView` 内；概览中的嵌入表格按行数确定高度，最多 420pt。名称区域可点击打开对话详情，并带 chevron；可见身份由项目名、所选范围内最近用量时间、短 ID 组成，完整信息通过悬停或详情查看。详情用 sheet 承载，提供明确的完成操作。

来源、扫描时间、API 等价估算与非订阅账单口径位于用量筛选下方。未定价与读取警告位于汇总之前；未知、未定价、部分、真实零值和过期不能折叠成同一显示状态。

同期比较仅出现在概览，标明上期日期，悬停可查看完整时段；对话与项目页只显示当前范围汇总，不显示上期日期或比较提示。

切换页面时，分组名称与路径只在首次遇到该组时生成；已知项目路径是目录，取名称时不通过文件系统推断类型。概览的横排与竖排候选布局共用一次排行计算，表格复用当前范围的费用汇总，避免重复统计挡住点击响应。

### Quota / Charts

额度块以名称、剩余百分比、进度条、恢复倒计时和重置时间组成一组。进度条作为数字的辅助图形隐藏于辅助功能树；百分比与错误文字保留语义。没有读数时显示空态，旧读数过期时保留时间与过期标记。

趋势图使用 Swift Charts 的柱形与轴标签，悬停显示时间、Tokens 和估算费用。热力图格子为 12–16pt、间隔 3pt；强度依次使用 `.teal` 透明度 0.25 / 0.45 / 0.70 / 1，无用量使用 `.secondary.opacity(0.10)`。未定价格用虚线框并配图例，悬停框和浮层不阻挡输入；图表数据保持文字辅助标签。

额度消耗趋势位于当前额度与公开重置动态之间。各额度窗口独立显示已用百分比折线，共用 24 小时 / 7 天范围切换，纵轴固定为 0–100%；颜色使用当前窗口的 `quotaColor`。单个观测显示点，重置或中断处不连线，悬停实测点时在该图标题行显示时间与读数，空白时段不补零。

### Menu Bar

沿用应用图标的原创缺口 Q，以单色模板轮廓与最多两个额度百分比组成紧凑入口；图标为 18pt，画布高 22pt，图文间距 3pt，字体取系统菜单栏等宽数字。无读数显示 `--`，读取错误附加 `!`；系统负责外观与选中着色，不把菜单栏绘成彩色状态徽章。

单击或右键均打开原生菜单，提供“打开面板”和“退出 Codex Quota”。打开面板复用同一窗口；菜单栏本身不直接唤起窗口。

## Do's and Don'ts

### Do

- **Do** 复用 `PanelTypography.detail`、`PanelButtonStyle`、`panelCard()` 与 `quotaColor`。
- **Do** 保留系统色和原生控件的语义，分别处理品牌、图表类别与额度状态。
- **Do** 用等宽数字、右对齐和一致单位支持比较，把来源、时间与必要口径贴近数据。
- **Do** 为截断名称保留完整值入口，为未知、部分和过期状态保留明确文字。
- **Do** 使用简短中文控件名，保留表单标签和必要错误信息。

### Don't

- **Don't** 从一张浅色截图固化系统背景、强调色、字体度量或玻璃材质。
- **Don't** 为了装饰增加大面积自造背景、阴影层级、字体或动画系统。
- **Don't** 用颜色独自表达类别或错误，也不要把未知额度显示成满额、缺价显示成免费。
- **Don't** 让长名称挤走核心数字，或把重要读取警告放到长页面末尾。
- **Don't** 把 HTML 示意、源码支持或单次窗口检查写成全尺寸、深色或无障碍验收通过。

配套 [.impeccable/design.json](.impeccable/design.json) 提供描述元数据与组件示意。色阶为展示用插值，HTML/CSS 仅帮助浏览文档，不能复刻 AppKit、SF Symbols 或 Liquid Glass，也不是原生代码的样式来源。
