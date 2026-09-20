# 只读恢复审计模型（2026-09-20）

新增 `Packages/ResidueRecovery`，补充先前日志只有粗粒度 succeeded/failed/unverified 的表达缺口：可表达完整历史计划、备份内容/元数据 hash receipt、逐步骤准备/结果时间，以及 file/runtime/registration/permission 四域效果。此轮只完成有界编码、校验与默认脱敏解释器，尚未持久化接入 SQLite/GUI；不将此报告描述为审计存储已完成。

## 安全语义

- audit envelope v1 与 SQLite journal schema1 分开；原数据库、原 API、默认打开策略均未修改，不做隐式迁移。
- canonical JSON payload 外包 schemaVersion 与 SHA-256。体积/数量/字符串有界，hash、版本、引用关系、顺序和未知字段检查失败即拒绝解释。
- SHA-256 是完整性检查，不是签名或授权。测试明确证明修改者可重算 hash；decode 成功仍不建立可信身份。
- decoded AuditPlan 没有到 VerifiedTransactionPlan/consent/token 的转换接口。报告只读，永不自动执行或补偿。
- backup receipt 只表示历史 hash 绑定，不能证明当前文件仍有效；报告固定要求重新验证。
- 脱敏 summary 不包含私有 ID、路径、软件名称、摘要或时间；保留步骤序号和四域结果。例如服务停止成功且登记 pendingSystemRefresh、随后文件动作 prepared 未决，分别呈现，不压缩成“全部成功”。
- auditClosed 可与失败结果并存，只是历史记账状态。完整原始 envelope 仍含隐私；未来存储必须在私有目录中采用本地 0600，本包没有文件写入。

## 实际验证

macOS 27.0（26A428）、Xcode 27.0（27A266a）、Apple Silicon，Swift 6。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueRecovery
```

10 个 Swift Testing 测试通过（参数化测试 5 案例，共 14 个具体案例），无失败或跳过。测试覆盖：完整计划/备份/四域结果 round-trip；部分成功+未决的默认脱敏报告；损坏 hash 与未知版本；未知字段（即使重新计算 hash）；未知 target/step/backup 引用、倒序时间和过多步骤；外层和解码后 payload 大小；未决 prepared 禁止关闭审计；已关闭审计保留失败效果；重新计算合法 hash 不建立真实性。

没有系统 mutation、真实备份读写、VM 或 helper 操作。下一步是独立设计审计数据与 durable claim/step 的原子绑定与显式 schema 迁移/新建策略，再接入只读恢复展示。当前模型不能保证跨系统事务、备份可用性或日志真实性。
