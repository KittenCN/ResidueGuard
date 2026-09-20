# ResidueRecovery

供只读恢复报告使用的历史审计数据格式与解释器。Swift 6、macOS 14、本地依赖 ResidueCore。没有 filesystem I/O、进程调用、GUI、恢复执行或 SQLite 迁移。

`AuditPlan(recording:)` 录入当时的完整计划字段：plan ID/digest、scope/profile/policy、创建/过期时间、确认次数、steps 和 targets。`BackupAuditReceipt` 保存 target 与内容/元数据 SHA-256 的历史观察绑定。`StepAuditObservation` 保存准备/结果时间和 file/runtime/registration/permission 四域结果；无结果的最后一步保留为 prepared 未决。`auditClosed` 只是审计结束，不能推断所有系统效果成功。

`RecoveryAudit.encode/decode` 使用 canonical sorted-key JSON、schemaVersion、base64 payload 和 SHA-256。未知版本、非规范编码、未知字段、损坏 hash、不合法引用/时间顺序/数量均拒绝。限制 envelope 180,000 字节、payload 131,072 字节、最多 256 targets/steps、字符串最多 1,024 UTF-8 字节；decode 先检查 envelope 大小再解析。

内容 hash 仅检查完整性，不是真实性、授权或数字签名。能修改数据并重算 hash 的同用户攻击者可以制造合法 envelope；这不能成为 trusted 数据。解码结果永远不能生成 VerifiedTransactionPlan、TransactionConsent、helper token 或系统执行命令。备份 receipt 不能保证备份文件现在仍存在、未损坏或可恢复。

`summary` 默认脱敏：只输出数量、步骤序号/action、四域效果和审计状态；不输出 target/step ID、名称、路径、指纹、摘要或时间。automaticExecutionAllowed/contentAuthenticityEstablished 永远 false；requiresReadOnlyReview/backupReverificationRequired 永远 true。未经脱敏的 snapshot 本身包含隐私数据，调用方未来持久化必须使用本地 0600、私有可信目录；本包目前不写文件，未与 schema1 journal 接通。

现有 SQLite schema1 和原 API 均未改变。后续如需持久审计，使用明确设计的 schema2 新建/迁移流程并保持 replay 数据；不可缺失时默默重建，也不能将普通导入报告视为执行源。

验证：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueRecovery
```

2026-09-20：10 个测试通过，参数化引用测试包含 5 个具体案例，无跳过。覆盖完整字段、损坏、未知版本/字段、引用/时间/数量错误、外层/内层体积边界、多步骤部分成功与失败、默认脱敏，以及重算 hash 不建立信任。
