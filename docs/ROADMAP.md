# 用量统计与通知改进计划

更新日期：2026-10-28。实施状态见下表；当前已支持的功能以 [README](../README.md) 为准。

目标是让用户能定位用量来源、看清项目总消耗、保留完整历史，并减少错过额度恢复提醒。继续采用原生 SwiftUI / AppKit，复用现有解析与计费逻辑。

## 实施顺序

| 优先级或状态 | 功能 | 主要收益 |
| --- | --- | --- |
| 已实现，待实机验收 | 引导开启持久通知 | 额度恢复提醒保留到用户手动关闭 |
| 已实现，待实机验收 | 对话用量明细与速度档位拆分 | 解释每段对话的消耗与费用来源 |
| 已实现，待实机验收 | worktree 归并到主项目 | 同一仓库的用量不再散落在多个路径下 |
| 已实现，待实机验收 | 小时趋势 | 看清一天内的消耗高峰 |
| 已实现，待实机验收 | 同期比较 | 判断用量与费用的变化 |
| 已实现，待实机验收 | 读取压缩日志 | 补齐压缩归档中的历史用量 |
| P2 | 保留历史统计 | 清理源日志后仍能查看已采集的用量 |
| P2 | Cursor 用量历史 | 补充账号全设备 Token 与服务端费用 |
| P2 | Antigravity 本地用量 | 补充本机会话的 Token 历史 |
| 暂缓 | 额度折算与用满预估 | 先解决账号归属与统计范围不一致的问题 |

P1 优先复用现有数据完成明细、归组和趋势；压缩读取单独处理解码依赖。P2 的持久化和新数据来源分别实施，避免一次扩大存储与统计口径。

## 引导开启持久通知

- [x] 在通知设置中引导用户开启“提醒保留到手动关闭”的系统样式。
- [ ] 完成系统设置跳转、返回状态更新及测试通知停留的人工验收。

已复用通知授权、各服务提醒开关、“系统设置”与“测试通知”入口，新增样式检测与原生引导弹窗。首次授权后自动引导一次；手动打开或自动显示引导时记住已展示状态，之后仅由用户主动打开。

交互要求：

1. 首次获得通知权限后，如果尚未采用持久样式，展示一次可跳过的轻量引导；已有用户可从设置页进入。用户跳过后不随刷新或启动反复弹出。
2. 引导提供“前往设置”和“暂不设置”。打开系统设置后，指向“通知 → Codex Quota Dock”，开启允许通知；macOS 26 及更新版本开启桌面提醒并选择“持续”，旧版选择“提醒”。应用名称取包内显示名称。
3. 设置页保留当前状态与现有“测试通知”入口。引导文案只需说明“让额度恢复提醒保留到手动关闭”。
4. 应用重新激活时读取 `UNNotificationSettings` 的 `authorizationStatus`、`alertSetting` 和 `alertStyle`。只有有效的持久提醒状态才显示已开启；未授权、未显示提醒、临时横幅和无法确认时分别如实显示。

持久样式由用户在系统设置中选择，应用只负责引导与读取状态。继续使用现有恢复事件和去重逻辑，不通过重复发送通知来维持显示。

验收：按实际改动检查引导可跳过、设置入口可打开、返回后状态更新；选择持久样式后发送一次测试通知，确认提醒保留到手动关闭。不要将授权成功或发送成功直接视为持久样式已经生效。

实现入口：`MonitorModel.updateNotificationStatus()`、`openNotificationSettings()`、`MainView` 的恢复通知区域，以及现有 `applicationDidBecomeActive` 回调。

依据：[Apple 通知设置](https://support.apple.com/zh-cn/guide/mac-help/mh40583/mac)、[`UNNotificationSettings.alertStyle`](https://developer.apple.com/documentation/usernotifications/unnotificationsettings/alertstyle)。

## 对话用量明细与速度档位拆分

- [x] 点击对话或高消耗对话，打开该对话的用量明细。

已使用原生明细面板展示所选范围内的记录与档位汇总；档位映射和计费共用，未知档位单独汇总。Token 显示精确整数，费用可悬停查看未舍入金额，沿用缺价状态。

现有核心检查（90 个断言）、应用检查（25 个断言）及编译通过；这些已有检查不覆盖新增明细交互，实机点击与拆分核对仍待验收。当前 Swift 默认构建系统为 `swiftbuild`，`scripts/test.sh` 的应用阶段仍按旧产物目录查找模块；本次按实际 `Products/Debug` 路径编译并运行同一份 `AppChecks.swift`，未修改测试代码。

展示每条已解析记录的时间、原始模型名、新增输入、输出、缓存读取、缓存写入、速度档位与估算费用；汇总 Standard / Fast / Ultrafast 的用量和费用。沿用当前日期和服务筛选，不读取消息正文或生成对话摘要。

现有 `UsageRecord` 已包含时间、模型、Token 分类和 `serviceTier`，费用复用 `UsagePricing`。缺少档位的旧日志沿用当前估算规则，不将估算标成实际账单，也不把缺价记录算成免费。

验收：明细合计与所选范围内的对话汇总一致，档位拆分能合回总额，“未定价 / 部分”状态一致。列表按日志记录呈现，不将其数量直接宣称为全部网络请求数。

参考：[cc-switch 请求详情](https://github.com/farion1231/cc-switch/blob/32db0e5763caa0ce5e91a378ccf0c8677f90a2bd/src/components/usage/RequestDetailPanel.tsx)、[cc-bar 对话分析](https://github.com/nanvon/cc-bar/blob/530ef49f3b5808e268181a55311e0c83cc40adff/README.md)。

## worktree 归并到主项目

- [x] 将可识别的 Git worktree 用量归入同一个主仓库。

后台扫描按不同工作目录只读解析 `.git` 与 `commondir`，支持相对路径和仓库子目录；概览、项目页及对话所属项目使用同一映射。原始记录不改写，对话明细的“工作目录”可查看原始路径与主项目。子仓库和子模块保持独立，无法确认归属的目录不按同名合并；已删除的 worktree 也不猜测归属，每轮刷新重新解析关系。

现有核心与应用检查共 115 个断言通过，编译通过；应用检查沿用上节的实际产物目录执行方式。未新增测试代码，已有检查不覆盖新的目录归属解析；实际多 worktree 数据和明细展示仍待人工核对。

验收：同一仓库的多个 worktree 汇为一个项目，总 Tokens 与费用不变；不同仓库即使同名也不混合。历史分支缺少日志证据时，不以当前检出的分支回填。

参考：[cc-bar ProjectWorktreeResolver](https://github.com/nanvon/cc-bar/blob/530ef49f3b5808e268181a55311e0c83cc40adff/Core/Usage/ProjectWorktreeResolver.swift)、[Git 仓库布局](https://git-scm.com/docs/gitrepository-layout)、[相对 commondir 识别问题 #8512](https://github.com/farion1231/cc-switch/issues/8512)（实施时仍开放）。

## 小时趋势与同期比较

- [x] 今天和昨天使用小时粒度，较长范围保留每日趋势。
- [x] 汇总增加与前一个等长期间的 Tokens、估算费用变化。

沿用 Mac 本地时区和现有服务筛选。今天对比昨天截至同一时间，昨天对比前天全天；最近 7 / 30 个自然日向前平移 7 / 30 天，保持相同的当地截止时刻。自定义范围按所选自然日数向前平移，标明对应比较区间；尚未结束的范围两期均截至对应时刻。“全部”不比较。

小时 / 每日柱形图、汇总及明细共用当前范围内的记录；比较从同一快照按相同服务筛选读取前期记录。变化卡片显示百分比与绝对变化量，上期为零显示新增量，费用缺价时停用费用变化；本期为空时仍保留零值与比较。沿用原有悬停明细、Tokens / 费用切换与缺价标记。

现有核心与应用检查共 115 个断言通过，应用检查沿用实际产物目录运行；未新增或修改测试代码。已有检查不覆盖新增的日期边界和图表交互，实机切换、悬停及同期数值核对仍待验收。

验收：小时与每日桶能合回同一范围总量；跨月和本地日期边界计算一致。前期为零时显示新增量，不显示无穷百分比；任一期间费用缺价时保留不完整状态，不给出误导性的费用涨跌百分比。

参考：[cc-switch 用量趋势](https://github.com/farion1231/cc-switch/blob/32db0e5763caa0ce5e91a378ccf0c8677f90a2bd/docs/user-manual/zh/4-proxy/4.4-usage.md)、[cc-bar 同期变化](https://github.com/nanvon/cc-bar/blob/530ef49f3b5808e268181a55311e0c83cc40adff/README.md)。

## 读取压缩日志

- [x] 支持 Codex `.jsonl.zst`，复用现有 JSONL 解析与去重。

已在 sessions / archived_sessions 扫描压缩日志，按 256 KiB 块解码后交给同一个 JSONL 解析器。剥离 `.zst` 后再提取会话 ID，普通与压缩副本使用同一去重键，沿用累计签名和 fork 重放处理。拼接帧继续解码，空文件、损坏或截断帧按读取失败处理；失败时仅保留该文件上次成功缓存，不缓存半份解压结果。压缩归档末尾的无效 JSON 也计入不完整提示。

静态编译 Zstandard v1.5.7 官方单文件解码源码及头文件，不加入远程 Swift 包或运行时动态库，不要求用户安装命令行工具，不落盘解压内容。采用 BSD 许可并随应用分发，来源和重新生成方式见 [第三方来源](../THIRD_PARTY_NOTICES.md)。

现有核心与应用检查共 115 个断言通过，默认构建与打包通过。检查入口补上 C 模块链接，并固定使用其所需的 native 对象目录；未增加或修改测试场景。已有检查不覆盖压缩日志解析，压缩前后统计、混合副本及损坏文件仍待人工核对。

验收：同一会话压缩前后统计一致；普通与压缩副本并存、active / archived 迁移和 fork 重放不重复入账。损坏或截断文件继续提示统计不完整，不补造用量。只有确实计入后才消除对应提示。

参考：[cc-bar ZstdStreamReader](https://github.com/nanvon/cc-bar/blob/530ef49f3b5808e268181a55311e0c83cc40adff/Core/Usage/ZstdStreamReader.swift)、[fork 重复统计问题](https://github.com/nanvon/cc-bar/issues/7)（已关闭）、[Zstandard 流式解码示例](https://github.com/facebook/zstd/blob/v1.5.7/examples/streaming_decompression.c)、[截断检测说明](https://github.com/facebook/zstd/issues/1109)。

## 保留历史统计

- [ ] 持久保存已采集的用量元数据，源日志被清理后仍可查看。

当前只使用内存缓存，源文件消失后相应用量会消失。保存去重标识、来源、时间、服务、会话、项目、模型、Token 与计费所需档位，不保存消息正文或凭据；保留 Token 明细，以支持价格变更后重算。

提供明确的本应用历史清理入口，区分重新扫描现存日志和清除已保存历史。旧日志已经删除且此前未采集的部分无法恢复。历史价格版本暂不扩展，继续按当前价格表估算并说明口径。

验收：重启和清理源日志后已采集的统计仍在；重复扫描不重复累计，价格变更可重算，主动清理范围清晰且不删除其他应用源日志。

参考：[cc-bar 历史保留说明](https://github.com/nanvon/cc-bar/blob/530ef49f3b5808e268181a55311e0c83cc40adff/README.md)、[UsageSnapshotStore](https://github.com/nanvon/cc-bar/blob/530ef49f3b5808e268181a55311e0c83cc40adff/Core/Storage/UsageSnapshotStore.swift)。

## Cursor 用量历史

- [ ] 接入远端用量事件，展示 Token、模型、请求数与服务端费用。

参考 cc-bar 的 `get-filtered-usage-events` 读取与分页处理。数据范围标为“账号全设备用量”；服务端费用与本地 API 等价估算分别呈现，缺少项目或会话信息时不强行归组。查询沿用现有只读登录态和已启用服务的凭据边界。

验收：分页与刷新不重复入账，账号切换不混合记录，费用缺失与零费用可区分；远端失败保留最后成功快照并标明过期。可查询的历史范围以接口实际返回为准。

参考：[cc-bar CursorUsageFetcher](https://github.com/nanvon/cc-bar/blob/530ef49f3b5808e268181a55311e0c83cc40adff/Core/Usage/CursorUsageFetcher.swift)。

## Antigravity 本地用量

- [ ] 读取本机 transcript 的实际 Token 字段，接入现有用量汇总。

参考 cc-switch 的会话导入逻辑，同时考虑 IDE 与 CLI 数据目录。相同会话在一个目录只有索引时，仍继续查找另一个目录的 transcript；避免旧对话新增用量被遮蔽。模型缺失时保留未知，不用当前模型设置猜测历史记录。

验收：旧对话追加用量能更新，两个目录的同会话不重复统计；按日志实际定义处理输入、缓存与推理 Token，缺少模型或定价时保留不完整状态。

参考：[cc-switch Antigravity 导入](https://github.com/farion1231/cc-switch/blob/32db0e5763caa0ce5e91a378ccf0c8677f90a2bd/src-tauri/src/services/session_usage_agy.rs)、[双目录遮蔽问题](https://github.com/farion1231/cc-switch/issues/8941)。

## 暂缓额度折算与用满预估

cc-bar 按本机周期消耗除以官方已用比例推算满额 Token / 费用。当前本机日志跨账号合并，而远端额度属于当前账号；其他设备的用量也不在本机记录中，不能直接套用该比例。

只有在账号归属、额度周期、样本覆盖范围和模型计量差异可解释后，再评估是否提供明确标为估算的结果。不将本地 Token 线性换算成官方剩余额度，也不据此触发恢复通知。

参考：[cc-bar CycleUsage](https://github.com/nanvon/cc-bar/blob/530ef49f3b5808e268181a55311e0c83cc40adff/Core/Usage/CycleUsage.swift)。

## 实施与验收约定

上述验收描述用于界定每项功能的完成标准；每次只验证当前改动及直接相邻流程，遵守 [AGENTS.md](../AGENTS.md) 的最小必要验收规则。没有明确请求时不新增或修改自动化测试代码，也不通过临时脚本补写测试。

参考代码基于 2026-10-28 查阅的 cc-switch `32db0e5` 与 cc-bar `530ef49`。实施前重新查看相关 issue 与修复状态；若改编代码，按其 MIT 许可保留来源和声明，并同步第三方许可文件。每项完成后更新本计划状态和 README 的实际行为说明。
