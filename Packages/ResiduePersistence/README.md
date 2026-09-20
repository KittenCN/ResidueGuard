# ResiduePersistence

P3 的独立 SQLite 事务日志原型，现支持默认 schema1 与显式 schema2 审计绑定。Swift 6、macOS 14 最低部署目标，链接系统 `sqlite3`，没有外部依赖。尚未接入 GUI、生产执行 gate、helper 或实际清理；不构成 P3/P4 集成验收。

## API 与调用顺序

调用方先准备当前有效用户拥有、无扩展 ACL、0700 的私有目录，然后只在明确首次初始化时调用 `TransactionJournal(directory:createNew: true)`。正常启动使用默认 `createNew: false`；数据库丢失、损坏、版本不支持均拒绝打开，不能用“删除数据库重试”恢复清理功能。`createNew: true` 也拒绝已存在数据库。

- `claim(planID:digest:nonce:)`：在 `BEGIN IMMEDIATE` 事务中原子占用计划 ID 与 nonce；任一已用即拒绝，完成/失败之后也不释放。
- `prepare(planID:operationID:)`：提交准备记录。调用方必须等成功返回后才允许相应外部操作；本包不会执行外部操作。
- `recordResult(planID:operationID:result:)`：记录 succeeded / failed / unverified。只有成功才能准备后续步骤；重复结果或重复操作拒绝。
- `finish(planID:)`：结束审计记账，允许失败结果，但存在未决 prepared 步骤时拒绝；它不表示系统操作成功或已回滚。
- `unfinishedEntries()`：在只读 SQL 快照事务中查询未完成计划和逐步结果，不续跑、不补偿、不改变任何记录。

claim 的 digest 是上层生成的不透明计划摘要；本包不验证摘要算法、授权、token 到期时间、调用方身份、计划操作集合、源指纹、备份或系统后置状态。接入前必须由已有安全 gate 分别验证这些条件。进程重开后 nonce 和 plan ID 仍被占用，不能以“恢复”名义重新执行计划。

## 存储约束

目录逐级用 `openat/O_NOFOLLOW` 打开，拒绝路径中的符号链接及不可信 owner；祖先不允许组/其他用户可写，root-owned sticky 临时根例外。最终目录必须当前有效用户拥有、0700、无扩展 ACL。文件必须 0600、当前有效用户拥有、单硬链接、普通文件、无扩展 ACL；数据库和目录身份在每次事务前后复核，异常使实例永久闭锁。既有 WAL/SHM 或不安全 journal sidecar 拒绝。测试使用明确的 `/private/tmp` 自有随机目录，避免 `/tmp`、`/var` symlink 别名。

schema1/schema2 均通过 SQLite application ID、user version、完整 schema（不允许额外 trigger）和 integrity/foreign-key 检查验证；每次事务重新核对版本/schema，不隐式迁移。使用 DELETE journal、synchronous FULL、macOS fullfsync，并读取确认配置；首次创建后 fsync 目录。SQLite 出错使实例闭锁，后续操作必须停止。没有清空日志、释放 nonce 或删除历史 API。

安全边界：SQLite 自身仍通过路径打开文件；目录 fd 锚与身份复核不是自定义 SQLite VFS，不能宣称抵御具有完全控制权的同 UID/root 恶意进程、存储介质回滚或真正断电。普通用户目录不可作为特权 helper 的可信 journal。实际接入须选定执行身份拥有的固定根目录，并增加断电和隔离 VM 的执行链测试；已完成的独立进程 SIGKILL 测试见下文。只读恢复查询可能由 SQLite 完成本应用数据库自身的 hot-journal 恢复；绝不触碰系统权限数据库。

## 已执行验证

2026-09-20，macOS 27.0 (26A428)，Xcode 27.0 (27A266a)：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePersistence
```

15 个 Swift Testing 用例通过：重新打开后 prepared/result 保留、计划与 nonce 防重放、失败不消耗其他 ID、双连接竞争 claim、状态顺序、失败/unverified 停止后续、未知版本/损坏/额外 trigger 拒绝、显式首次创建、权限/ACL/符号链接/硬链接/目录替换与实例闭锁。所有写入及 ACL 夹具均在测试自有随机临时目录；没有卸载服务、重置权限、安装 helper 或清理真实软件。

这是宿主上临时文件和系统 SQLite 的包测试，不是 VM mutation 验收或真实断电持久性证明。首次测试暴露临时路径别名和 ACL API 语义问题，修正后通过；无跳过用例。

## 独立进程崩溃验证

同一测试命令现运行 16 个 Swift Testing 测试，其中新增的参数化测试包含 5 个独立 writer / verifier 进程案例：claim、prepared、result、finished 提交后 SIGKILL，以及未提交 SQLite 事务实际刷出脏页后 SIGKILL。writer 明确达到阶段后，测试父进程发 SIGKILL 并核对退出信号；第二个新进程检查恢复记录并拒绝旧 plan ID / nonce。恢复查询前后状态一致，不自动重放 prepared 动作；finished 计划虽不再出现在未完成查询中，重放仍被拒绝。

`JournalCrashProbe` 是测试辅助 executable target，依赖库 API 和系统 SQLite，未列为 package 产品，未接入 GUI 或生产执行。它只接受 `/private/tmp/ResidueJournalCrashTests-*` 自有临时目录，目录与数据库安全性继续由 TransactionJournal 核验。未提交案例使用公开 `sqlite3_db_cacheflush` 并确认 hot journal magic，避免将仅在内存中发生的更新误称为磁盘恢复验证。

2026-09-20 最终运行：16 个测试通过（包括新增 5 个参数案例），无跳过。详细记录见 `docs/validation/journal-crash-results-2026-09-20.md`（仓库根目录）。SIGKILL 不等于真实掉电；没有验证介质故障、磁盘回滚或系统 mutation 原子性。

## 显式 schema2 审计绑定

原 `init(directory:createNew:)` 和四个粗日志写 API 继续使用 schema1，不隐式升级。schema2 用 `init(directory:createNew:schema: .auditV2)` 明确创建/打开；打开旧库会拒绝，只有显式 `TransactionJournal.migrateLegacyToAuditV2(directory:)` 在 BEGIN EXCLUSIVE 事务中升级。迁移保留原 plans、steps、nonce，为已有计划写入 legacy_plans 标记。默认 schema1 打开已升级库会拒绝，旧 schema1 活连接下一次事务检查也会拒绝。未知版本不迁移。

新写 API：

- `claimAudited(nonce:plan:)` 接受本进程创建的不可变 VerifiedTransactionPlan，内部构建 AuditPlan；plan row、原始完整 plan_payload 与 envelope 同事务提交。没有接受导入 envelope/snapshot 的写入接口。
- `prepareAudited(plan:step:backupReceipts:at:)` 完整比较原始计划字段、严格步骤顺序，并在 prepared 前绑定全部目标的备份历史 hash receipt。receipt 不是备份当前有效或已重新核验的保证；所有真实验证仍属执行侧职责。
- `recordAuditedResult(plan:step:effects:at:)` 原样记录四域效果，与 coarse result 同事务提交。失败优先，其余复用 Core `isVerified(for:)` 分类，不复制策略；越界/未知效果不能推进下一步。
- `finishAudited(plan:)` 关闭审计，不代表清理成功；允许零步骤或已失败结果的审计结束，拒绝 pending prepared。结束仍保留防重放。
- `recoveryEntries(includeFinished:)` 返回完整只读 audit 或明确 legacyEvidenceUnavailable。没有自动补造旧材料、重试、执行或恢复。旧四个写 API 在 schema2 一律拒绝，不能绕过审计。

新表 audits 同时保留不可变初始 plan_payload 与当前完整 envelope，每次读写核对完整 plan 内容、plan ID/digest、步骤序号/结果、结束标记和原表。legacy_plans 标记避免被删除的 audit 误认作旧数据；不一致使实例闭锁。内容 hash 是完整性检查，不是签名/认证；同 UID 完全控制数据库者可同时伪造多份数据，本包不承诺防篡改认证。

schema2 有显式资源上限：数据库文件 64 MiB、512 个计划、8192 步、完整审计 JSON 累计 8 MiB；单 envelope/plan 先在 SQL 限制字节长度再取出。先检查预算再遍历；超限拒绝，不删除历史或释放 nonce。新写超限在事务内回滚；超限 schema1 迁移拒绝且原数据/版本保留。当前是有界全量一致性检查，没有分页性能承诺；达到预算后需另行设计保留防重放的归档流程。

最终 schema2 验证：27 个 Swift Testing 测试通过，包含 13 个独立进程崩溃参数案例（旧 5、新 8）以及 5 个审计不一致参数案例。原有 16 个测试均回归通过。新增 COMMIT 前崩溃使用 DEBUG-only 内部 TaskLocal 检查点，在真实 migration/prepare/result 代码的同库事务中显式 cacheflush 并确认 hot-journal magic 后 SIGKILL；独立新进程验证全部旧状态或全部新状态，不出现半份 coarse/audit 写入。检查点不在公共 API，Release 编译不包含此注入逻辑。

详细结果与限制见仓库 `docs/validation/journal-schema2-results-2026-09-20.md`。PersistentTransactionDriver 仍使用 schema1；本轮不将占位 hash receipt 接入系统驱动，不声称 App 已自动记录全部清理审计。
