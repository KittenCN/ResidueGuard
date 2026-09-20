# Journal schema2 完整审计绑定（2026-09-20）

## 变更与边界

ResiduePersistence 新增显式 schema2 API、同库审计绑定、显式迁移、每次事务版本/schema 复核和有界一致性检查。依赖现有 Core/Recovery；没有修改 App、GUI、Xcode 工程或启用系统驱动。现有 PersistentTransactionDriver 仍使用 schema1，后续需要真正受限 driver 提供真实备份观察，不能用占位 hash 冒充验证。

默认 schema1 行为保留；schema2 创建/打开必须显式选择。迁移使用 BEGIN EXCLUSIVE，同事务创建 audits/legacy_plans 并变更 user_version；不重建 plans/steps、不丢弃 nonce、不自动清空历史。旧记录保留并返回 legacyEvidenceUnavailable；旧活连接每次事务检查版本，迁移后不能继续写。旧粗日志 mutation API 在 schema2 全部拒绝。

schema2 claim 的输入是不可变 VerifiedTransactionPlan，内部构造历史 AuditPlan；没有持久化用户导入 envelope 的 API。原始完整 plan_payload 与当前 envelope 同库保存，每次读写核对完整计划字段与 coarse plan/digest/steps/finished；不是仅比较调用者给出的任意摘要。prepare 绑定全部目标的历史 backup receipt；result 保留四域效果并复用 Core `isVerified(for:)`；finish 表示审计结束，可包含失败或零步骤，不是清理完成。

所有 envelope/step 状态与原日志修改在同一 SQLite 事务。未知版本/结构、损坏、引用不一致或遗失审计拒绝并闭锁；独立 legacy 标记避免误把 audit 删除解释为旧材料缺失。

资源边界：schema2 数据库 64 MiB、计划 512、步骤 8192、审计 JSON 总计 8 MiB；单行 envelope 180,000 字节、plan_payload 131,072 字节。读取先在 SQL 检查数量/字节预算，再加载记录；单行用 CASE 限制取回内容。超限新写在事务内回滚，超限迁移不改变旧库。没有自动删历史或释放 nonce，也未实现达到预算后的归档。仍是有界全量一致性检查，不夸大性能。

## 实际测试

环境 macOS 27.0（26A428）、Xcode 27.0（27A266a）、Apple Silicon，Swift 6、系统 SQLite。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePersistence
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path Packages/ResiduePersistence -c release
```

Release 整包构建成功（6.42 秒），包括辅助 executable 的非 DEBUG 编译。

Debug 最终结果：**27 个 Swift Testing 测试通过**（0.320 秒），原有 16 个测试全部回归，无失败或跳过。其中特别包含：

- 13 个独立 writer/verifier 进程 SIGKILL 参数案例：原 5 个 schema1 案例；新增 audited claim/prepared/result/finished 已提交四阶段、prepare/result COMMIT 前两阶段、migration COMMIT 前/后两阶段。
- 5 个不一致参数案例：audit 遗失、envelope 损坏、coarse digest 不符、未知版本、原始 plan_payload 不符。
- 真实关闭/重开保存完整计划、backup receipt 和四域结果；plan/nonce 重放仍拒绝。
- 旧库有 prepared 步骤的迁移无数据丢失，旧活连接拒写，重复迁移明确拒绝。
- schema2 旧 API 绕过拒绝；非法准备/倒序时间的事务不留下半份步骤；失败/越界效果不能继续。
- 即使重新计算 envelope hash，改变初始完整计划字段也会与 plan_payload 不符而拒绝；Recovery 本身的 hash 通过不建立数据库记录真实性。
- 512 计划边界、新 claim 超限回滚、超限旧库迁移保留 schema/nonce、过大审计 JSON 与过大 DB 在加载前拒绝。

COMMIT 前故障使用仅 DEBUG 编译的内部 TaskLocal 检查点，调用真实迁移/事务实现。在暂停前调用公开 sqlite3_db_cacheflush，并验证非零 hot-journal magic；父进程发 SIGKILL，不跑析构/正常关闭，再用独立进程重开。prepare/result 的 coarse 与 envelope 一起回到旧状态；迁移前崩溃回到完整 schema1，迁移后崩溃读到完整 schema2，旧 nonce 始终保留。Release 不包含检查点注入逻辑，Release 模式崩溃参数测试仅保留无需该辅助入口的旧五例。

## 限制

这证明进程突然退出和实际 SQLite hot-journal 恢复，不证明真实断电、磁盘介质故障、介质回滚或跨系统事务。内容 hash/双份 plan 字段仍不构成对具有同 UID 完全控制权者的认证。backup receipt 只记录历史观察，不保证当前备份存在、有效、元数据可恢复或已经重新核验。

恢复 API 只读；没有从 decoded snapshot 生成 VerifiedTransactionPlan/consent/token，也不自动恢复、重试或重启服务。所有测试限自有随机临时目录与合成计划，无真实系统服务、权限或软件清理。

本地日志 `.local-evidence/persistence-schema2-final.log` 与 `persistence-schema2-release.log` 不提交。完整公共 API 与集成边界见 `Packages/ResiduePersistence/README.md`。
