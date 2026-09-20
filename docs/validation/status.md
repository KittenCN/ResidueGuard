# 项目当前状态

更新：2026-09-20。目标为本地运行与隔离 VM 验收；暂不要求 App Store、Developer ID 或公证。**全项目尚未完成，生产系统修改保持关闭。**

- 原生 SwiftUI App 支持显式目录只读扫描、合成演示、dry-run、脱敏报告、权限引导；新增历史审计报告只读导入页。
- VM 中修复目录已授权但读取上级目录失败导致零行的问题：同一自有目录实际返回 1 条；目标未授权仍为无法核实，不误标红。
- Core 40 项、Transactions 6 项通过：修复未验证注册状态仍可完成事务的错误，两层共用结果判断。见[修复证据](transaction-outcome-fix-2026-09-20.md)。
- Platform 39 项、Persistence 27 项、Backup 40 项通过。日志含 13 个独立进程 SIGKILL 场景（含schema2审计写入与迁移）；VM 固定自有夹具的只读备份及精确 runtime 探针通过。
- Quarantine 38 项、Recovery 10 项通过：临时夹具备份核验、同卷不覆盖隔离/恢复和只读恢复检查；审计模型保持内容完整性与来源真实性分离。没有生产构造入口。
- AuditImport 15 项真实文件测试通过，App 已接入；其后 History UI 4 通过、1 系统 picker 跳过、0 失败。
- GUI 最新全量结果：18 项中 17 通过、1 显式跳过、0 失败（224.780 秒）。跳过系统 picker 自动输入；随后另行在VM Release实际选择文件并导入显示成功，不能据此改写XCTest结果。新文件读取模块集成的验证见[导入报告](history-report-import-2026-09-20.md)。
- 固定自有 VM 隔离/恢复 probe 已实现，Backup 40 + Quarantine 38 项临时文件测试通过；宿主拒绝（exit77）、参数拒绝（exit64）。客体固定正常往返已实际退出0并完成各次核验，见[受限实验上下文](owned-fixture-context-2026-09-20.md)。
- 本地 Release 已构建并验证双架构签名、只读沙盒与无调试授权；见[签名验证](local-release-signing-2026-09-20.md)。
- VM 真实 XPC 五场景通过：正确 peer 可通信、错误 client/server 拒绝、同一二进制更正约束后成功，并验证自有进程退出。仍是无特权实验，外部 harness 配置不是生产信任根；未安装 helper。

最新专项证据：[VM GUI](vm-gui-scan-2026-09-20.md)、[系统实验](vm-system-results-2026-09-20.md)、[日志崩溃](journal-crash-results-2026-09-20.md)、[备份](backup-results-2026-09-20.md)、[隔离](quarantine-results-2026-09-20.md)、[恢复核验](recovery-inspection-results-2026-09-20.md)、[IPC](ipc-transport-experiment-2026-09-20.md)。

schema2完整审计同库绑定及显式迁移已实现，旧nonce保留，旧连接拒写；默认driver仍schema1，详见[日志升级](journal-schema2-results-2026-09-20.md)。

实际剩余门槛见[安全门审查](user-cleanup-gate-review.md)：完整影响/身份、固定 VM 真实事务 driver、持久恢复绑定、竞争与故障矩阵、helper 生命周期、多系统及可访问性。并发替换源对象的竞争尚未解决，不能把临时夹具通过推断为第三方清理安全。

历史文档的“等待 VM 登录”“journal 未实现”已过时；签名分发身份不是继续编码的前置条件。当前范围见[本地开发说明](local-development-scope.md)。

保留规则已接入：显式30天、只增加保护不隐藏、不改变存在状态；合成规则仅会话内，真实来源绑定身份/内容指纹。Preferences 22项通过，VM已实际保存并在应用重启后读取自有夹具规则。详见[保留规则](retention-rules-2026-09-20.md)。

真实备份审计桥新增身份/内容/元数据/manifest绑定；修复标准Library限制性ACL与hidden父锚点兼容问题后，固定VM往返及前后证据核验exit0，仍未集成持久实验审计。见[证据桥](backup-audit-evidence-2026-09-20.md)。
