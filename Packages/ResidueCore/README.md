# ResidueCore (P1)

Swift 6 / macOS 14+ 纯策略库。无 SwiftUI、Process、系统扫描或执行器；没有授权真实写操作的 API。

- `SourceRecord` / `ProviderResult`：保留作用域限定身份、原始来源、解析警告与覆盖；来源失败不能伪装为空扫描成功。
- `OrphanClassifier`：高可信残留需要完整覆盖、明确身份、所有目标缺失、稳定复核和证据；离线、权限不足、废纸篓、共享活跃、安装中、运行反证均阻止标红。
- `DryRunPlanner`：先合并同一底层操作的所有影响，再检查每项精确能力、OS build、身份/指纹、保护状态和范围。冲突、未知、缺失和过期均阻断。
- `ConsentSession`：独立呈现事件，一次/两次确认、第二次风险短语、到期和摘要变化失效；完成只代表 dry-run 演示结束。

能力、存在证据和指纹由调用方提供，仅用于 P1 合成测试。未来真实写入不能信任这些输入，必须独立重新验证来源、影响集合、签名、备份和授权。`supportedVerified` 合成 profile 不是 macOS 集成验证。

根目录运行 `bash script/test.sh`。测试读取根 `fixtures/confirmation-cases.json` 的 F01–F24，另外覆盖影响扩展、去重/冲突、过期、重装指纹、独立确认/重放、能力维度和保守存在性。CLT 环境可能缺少 Swift Testing 插件，使用项目固定完整 Xcode。

## P3 事务／恢复准备（合成验证）

新增 `VerifiedTransactionPlan`、`TransactionCoordinator`、`TransactionDriver`、`RecoveryPolicy`。这是纯策略与注入接口框架，不是生产清理实现。默认 gate 为 `closed`；唯一可开启路径明确命名 `syntheticTests`，没有生产开启模式。应用不接入 driver；没有 Process、文件写入、服务操作或提权实现。`DryRunPlan` 不能传入事务协调器。

计划只接受 currentUser 作用域和固定 synthetic-transaction-v1 合成 profile；机器共享、未知作用域及其他 profile 全部拒绝。计划校验绑定完整影响、作用域、profile、源指纹、步骤依赖和有效期；允许的步骤仅为精确服务停止、启动配置隔离。完整授权、所有目标备份校验和日志准备必须先于效果；每步在日志等待后再次核验。失败立即停止后续步骤，记录文件／运行时／登记／权限的独立结果，不承诺回滚。抛出异常的效果一律视为可能部分发生、结果未验证。备份和日志故障、指纹改变、服务失败、重放（包括换 nonce 重放同一计划）和取消均由 fake driver 注入测试。动作不允许报告权限变化，停止服务不允许额外文件变化，隔离文件不允许额外运行时变化；异常效果保留记录并立即停止。

`Verified` 只表示通过纯数据校验，不表示 OS 已验证。调用方提供的 consent、scope、profile、指纹和 driver 返回值仍属于未建立信任的输入；不能成为 helper 凭据。将来平台必须独立认证客户端、验证能力与实际影响、持久化原子防重放、验证备份安全存储，并在实际效果边界用已验证句柄关闭 TOCTOU。当前协调器只提供进程内互斥，跨进程／崩溃恢复依赖未来可信 driver 的持久化实现。未实现真实日志存储、备份/隔离、bootout、恢复、管理员授权或 OS 集成测试。

恢复策略仅产出新计划需求。目标存在、软件重装、备份不可信或元数据/身份/范围未知会阻断；旧权限不可恢复，恢复配置不允许自动重启服务。所有系统能力仍未验证／禁用。
