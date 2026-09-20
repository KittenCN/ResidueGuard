# ResidueTransactions

Core 纯事务协调器与 Persistence SQLite 日志之间的合成测试桥。最低 macOS 14、Swift 6、本地包依赖；不执行进程、不包含文件隔离、launchctl、权限重置、helper 或 GUI 接口，也不增加 production-enabled gate。

`PersistentTransactionDriver` 实现 Core 的 `TransactionDriver`：

- `claim` 将不可变 plan ID / digest 和 nonce 原子写入 TransactionJournal；重放返回 false，存储故障抛出，delegate 不会先于持久 claim 调用。
- `journalPrepared` 严格按计划顺序提交 prepared，成功返回后才允许该实例调用 delegate.perform；重复、跳步及直接跳过 prepared 均拒绝。
- `journalResult` 在 Core 最终检查前自行检查 effect 范围与所需效果，避免把越界/未知效果记为 succeeded。failed 映射 failed；required effect 非 succeeded、permission 非 notAttempted、bootout 意外改变 file、quarantine 意外改变 runtime 或 registration unverified，映射 unverified 并阻止后续动作。registration pendingSystemRefresh 可与本步骤成功并存，但不表示后台历史已清除。
- `finalize(plan:report:)` 必须在 coordinator 返回 completed 后由调用方显式调用。核对计划、全部步骤和结果后结束日志；最后一个 journalResult 不会提前标记 finished。取消、失败、异常和未 finalise 的计划保留在未完成查询中，后续只读复核。

`TransactionOperations` 只注入 authorize / revalidate / prepareBackup / perform，所有参数使用 Core 的计划/步骤/目标模型。它是内部测试集成接口，不是 IPC 或任意路径/命令接口。桥只服务一个 claim；重新创建实例不会绕过 SQLite 防重放。Core 默认 closed，唯一可运行 gate 仍为 syntheticTests，VerifiedTransactionPlan 只接受 synthetic profile。

边界：这不是完整生产驱动或授权边界，delegate 的系统身份验证/备份/执行职责不能由此替代。当前日志 schema 仅保存计划摘要、步骤 ID 和 coarse result，没有完整计划内容、逐域 effect、备份 manifest 或恢复身份，不能据此重建执行或恢复命令。包未接入 GUI，尚未进行 VM 系统事务验证。

验证：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueTransactions
```

2026-09-20：6 个测试通过，包含 14 个具体案例（7 个效果异常、3 个日志错误、4 个基础测试），没有跳过。所有 SQLite 数据及 chmod 故障夹具均在测试自有 `/private/tmp/ResidueTransactionsTests-*` 目录；delegate 无任何真实系统效果。详见仓库 `docs/validation/persistent-transaction-bridge-2026-09-20.md`。
