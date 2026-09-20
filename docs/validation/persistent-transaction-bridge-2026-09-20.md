# 持久事务测试桥（2026-09-20）

新增独立 `Packages/ResidueTransactions`，连接 Core TransactionCoordinator 与 Persistence TransactionJournal。没有修改 Core/Persistence，也没有开启生产执行、接入 GUI、调用系统服务或安装 helper。

## 根本约束

Core 先调用 journalResult，再判断返回效果是否属于该步骤的合法范围。桥不能简单地把 runtime/file 任一 succeeded 映射为持久成功，否则意外权限变化或越界文件变化会留下错误日志，并可能允许后续 prepare。

因此桥按 action 独立验证 effect，再映射 succeeded / failed / unverified；任何 invalid/unknown effect 都不能被记录为成功。registration pendingSystemRefresh 只表示系统历史待刷新。registration unverified 比 Core 当前策略更保守，桥记录 unverified 并闭锁后续步骤。

持久写失败会阻断执行：claim 失败零 delegate 调用，prepare 失败零 perform，result 失败不执行后续隔离。result 写失败后 prepared 状态保留，为只读恢复明确保留“操作结果未知”。整个计划的 finish 只接受 coordinator 返回的完整成功报告，不在最后一个步骤写入时提前完成。

## 实际测试

环境：macOS 27.0（26A428）、Xcode 27.0（27A266a）、Apple Silicon，Swift 6，本地系统 SQLite。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueTransactions
```

13:29 运行构建成功（4.53 秒），6 个 Swift Testing 测试通过（0.049 秒），包括 14 个具体案例：

- 正常合成序列：authorize 时数据库已有 claim，perform 时已有对应 prepared，备份先于 perform；显式 finalize 后未完成查询为空。
- 重开 SQLite、重新创建 coordinator 和 driver 后，旧 plan ID 或旧 nonce 仍被拒绝，零 delegate 调用。
- 默认 closed gate 零 claim 和零 delegate。
- 跳过 prepared 或颠倒步骤顺序拒绝。
- 七种异常：失败、所需效果 unverified、所需效果缺失、越界 permission、bootout 越界 file、registration unverified、perform 抛错。均没有后续 isolate，日志无错误 succeeded。
- 三种 SQLite 故障：claim、prepare、result 边界将自有 journal 文件权限改为不安全模式。全部报告 journalFailed，阻止相应后续操作；result 故障留下 prepared 未决记录。

所有操作仅发生在自有随机临时目录。delegate 只返回合成效果并检查真实 SQLite 状态，无实际服务、文件清理、权限重置或 VM mutation。没有测试失败或跳过；不将包测试标记为 OS 集成通过。

## 剩余边界

这只是后续 VM driver 的持久记账基础。当前 schema 没有完整计划、逐域 effect 和备份 manifest；未完成记录必须只读核查，不能自动构造执行/恢复。未验证系统效果与 SQLite 之间的跨系统事务、helper 调用方认证、断电/介质故障或真实文件隔离。生产 gate 仍关闭。
