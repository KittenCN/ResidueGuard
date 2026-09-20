# 项目当前状态

更新：2026-09-20。目标为本地运行与隔离 VM 验收；暂不要求 App Store、Developer ID 或公证。**全项目尚未完成，生产系统修改保持关闭。**

- 原生 SwiftUI App 支持显式目录只读扫描、合成演示、dry-run、脱敏报告、权限引导；新增历史审计报告只读导入页。
- VM 中修复目录已授权但读取上级目录失败导致零行的问题：同一自有目录实际返回 1 条；目标未授权仍为无法核实，不误标红。
- Core 60 项、Transactions 6 项通过：修复未验证注册状态仍可完成事务的错误，两层共用结果判断。见[修复证据](transaction-outcome-fix-2026-09-20.md)。
- Platform 50 项、Persistence 41 项、Backup 54 项通过。日志含 18 个独立进程 SIGKILL 场景（含schema2审计写入与迁移）；VM 固定自有夹具的只读备份及精确 runtime 探针通过。
- Quarantine 79 项、Recovery 20 项通过：临时夹具备份核验、同卷不覆盖隔离/恢复和只读恢复检查；审计模型保持内容完整性与来源真实性分离。没有生产构造入口。
- AuditImport 15 项真实文件测试通过，App 已接入；其后 History UI 4 通过、1 系统 picker 跳过、0 失败。
- GUI 最新全量结果：22 项中 21 通过、1 显式跳过、0 失败（273.497 秒）。跳过系统 picker 自动输入；随后另行在VM Release实际选择文件并导入显示成功，不能据此改写XCTest结果。新文件读取模块集成的验证见[导入报告](history-report-import-2026-09-20.md)。
- 固定自有 VM 隔离/恢复 probe 已实现，最新 Backup 54 + Quarantine 79 项测试通过（历史阶段计数见专项报告）；宿主拒绝（exit77）、参数拒绝（exit64）。客体固定正常往返已实际退出0并完成各次核验，见[受限实验上下文](owned-fixture-context-2026-09-20.md)。
- 本地 Release 已构建并验证双架构签名、只读沙盒与无调试授权；见[签名验证](local-release-signing-2026-09-20.md)。
- VM 真实 XPC 五场景通过：正确 peer 可通信、错误 client/server 拒绝、同一二进制更正约束后成功，并验证自有进程退出。仍是无特权实验，外部 harness 配置不是生产信任根；未安装 helper。

最新专项证据：[VM GUI](vm-gui-scan-2026-09-20.md)、[系统实验](vm-system-results-2026-09-20.md)、[日志崩溃](journal-crash-results-2026-09-20.md)、[备份](backup-results-2026-09-20.md)、[隔离](quarantine-results-2026-09-20.md)、[恢复核验](recovery-inspection-results-2026-09-20.md)、[IPC](ipc-transport-experiment-2026-09-20.md)。

schema2完整审计同库绑定及显式迁移已实现，旧nonce保留，旧连接拒写；默认driver仍schema1，详见[日志升级](journal-schema2-results-2026-09-20.md)。

实际剩余门槛见[安全门审查](user-cleanup-gate-review.md)：完整影响/身份、第三方真实事务 driver、完整运行态证据与新恢复计划授权、竞争与故障矩阵、helper 生命周期、多系统及可访问性。并发替换源对象的竞争尚未解决，不能把临时夹具通过推断为第三方清理安全。

历史文档的“等待 VM 登录”“journal 未实现”已过时；签名分发身份不是继续编码的前置条件。当前范围见[本地开发说明](local-development-scope.md)。

保留规则已接入：显式30天、只增加保护不隐藏、不改变存在状态；合成规则仅会话内，真实来源绑定身份/内容指纹。Preferences 22项通过，VM已实际保存并在应用重启后读取自有夹具规则。详见[保留规则](retention-rules-2026-09-20.md)。

真实备份审计桥新增身份/内容/元数据/manifest绑定；修复标准Library限制性ACL与hidden父锚点兼容问题后，固定VM往返及前后证据核验exit0，后续已接入独立持久实验日志（见下）。见[证据桥](backup-audit-evidence-2026-09-20.md)。

P2候选归属图与应用实例页已接入，保留多副本/冲突/可能共享线索但不提升存在判断或清理权限；Core新增10项、Platform新增3项、候选图GUI2项通过。见[候选图验证](candidate-ownership-graph-2026-09-20.md)。

BTM独立VM只读探针在5秒与30秒预算下均超时、双流为空，原因未知；产品维持unsupported，未提权或读取私库。见[研究与实测](btm-readonly-research-2026-09-20.md)。启动脚本已按项目可执行文件路径定位进程，实际Debug启动验证通过，见[启动验证](project-launch-verification-2026-09-20.md)。

固定VM实验已接入独立持久日志，最终v7往返exit0，两步prepare/result与严格只读重开通过；另一个进程只读比较历史/源/隔离文件成功。Backup54、Quarantine53、Persistence41项通过，后者含18个进程崩溃场景。见[VM日志集成](owned-experiment-journal-2026-09-20.md)、[独立日志约束](owned-fixture-experiment-journal-2026-09-20.md)、[只读根枚举](owned-fixture-audit-reader-2026-09-20.md)。runtime来源字段已在新实验记录，旧记录缺失不会补造；VM动作中断矩阵与恢复新授权仍待完成；历史数据不授予执行能力。

最新VM v8往返已持久保存两步runtime provenance；独立reader v2同时读到3条新旧实验，旧两条证据步数0、新一条2，均源匹配/隔离为空、无授权。Platform47、Persistence41、Backup54、Quarantine53项通过。

覆盖范围约束的快照比较与已授权配置根局部复扫已接入：不完整/未请求范围不产生负面观察、不替换完整基线，比较移出主线程。Core59项通过（含10,000记录比较约0.23秒），GUI22项中21通过/1显式跳过/0失败。见[快照比较验证](coverage-aware-snapshot-diff-2026-09-20.md)。

固定自有VM bootout单次实测exit0，源/程序未变；后置print113仍保留unknown，不自动bootstrap/隔离。Quarantine76项通过（含Bootout13项和独立reader4项），独立只读进程VM核验exit0，1条/4槽、0失败、无执行授权。见[服务实验](owned-fixture-bootout-results-2026-09-20.md)。源身份到rename之间未找到公开原子绑定接口，第三方gate继续关闭，见[竞争研究](source-identity-race-research-2026-09-20.md)。

P4新增有界HelperRequest wire codec：16KiB/深度/字符串限制，严格规范字节与版本/字段校验；Security23项通过。未连接真实认证或executor，解析成功不产生权限。见[wire验证](helper-wire-codec-2026-09-20.md)。

独立Bootout日志新增3处真实进程SIGKILL边界：intent后、合成issued后/outcome前、outcome后；另一个只读进程验证pending/known历史并保持全部文件字节不变。全部系统命令为合成注入，不算真实服务中断验收。完整Quarantine79项通过。详见[日志审计及崩溃记录](owned-fixture-bootout-audit-reader-2026-09-20.md)。

10,000条容量：新增定向GUI仅验收全量总数和末尾筛选，1项通过（18.358秒）；原完整XCTest受AX幻影Dialog阻断，失败记录保留。VM实际鼠标/键盘补验加载/筛选/清空/滚动/取消通过，未声称200ms或VoiceOver验收。最新Release双架构签名及8个Debug标记隔离检查通过。见[容量专项](large-scan-gui-fixture-2026-09-20.md)。

精确服务错误文本新增只读诊断元数据；runtime仍unknown、coverage partial，不产生不存在证明。Platform最新49项通过，见[诊断反例](scoped-diagnostic-notfound-research-2026-09-20.md)。

有界status-only XPC实验已修正GUI与服务审计会话的角色混淆；10项模型测试通过，真实VM17场景全部通过并逐个核验自有进程退出。保留v1/v2失败；外部manifest不是生产信任根，未安装helper或接执行器。见[会话与wire实验](status-wire-xpc-experiment-2026-09-20.md)。

只读索引/候选图新增移动、同ID/同名不同签名提示和暂缺后恢复的边界补测：Core60、Platform50项通过，四阶段行存在性显式验证。只证明不变红/不产生执行能力，不是有效签名替代安装或真实updater全矩阵验收，见[误判边界](index-candidate-misclassification-matrix-2026-09-20.md)。

最小窗口定向GUI回归1项通过、0失败/跳过（23.071秒）：实际980×692点，双确认按钮可达，第二确认可用时Escape取消，重开须重新批准范围。未改变生产UI，未重跑全量GUI；不等于完整VoiceOver/高对比度验收。见[小窗口与键盘](minimum-window-keyboard-2026-09-20.md)。

独立合成恢复新计划与双确认模型新增10项，Recovery全量20项通过。全部产物permitsMutation=false，未接fresh文件核验、历史导入授权或真实执行；见[恢复合成模型](synthetic-recovery-consent-2026-09-20.md)。
