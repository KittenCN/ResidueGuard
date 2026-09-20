# 独立进程日志崩溃恢复验证（2026-09-20）

## 范围与环境

宿主 macOS 27.0（26A428）、Apple Silicon、Xcode 27.0（27A266a），系统 SQLite，Swift 6 包。测试只在自己创建的 0700 随机临时目录中创建/修改数据库；没有服务卸载、权限重置、helper 安装、真实软件清理或 VM 系统状态修改。

这次补齐 P3 日志层的独立进程突然退出证据，不表示 P3 清理事务或 P4 helper 集成完成，不改变任何生产 mutation gate。

## 实现

新增测试辅助 `JournalCrashProbe` executable target（不作为 package 产品，不接入 App），测试 target 依赖它以保证构建。父测试进程创建专用临时目录并启动 writer。writer 达到指定状态后写 readiness 标记并等待；父进程确认 ready 后向该子进程发 SIGKILL，验证退出原因与信号。随后启动全新的 verifier 进程重新打开 TransactionJournal。

| 杀进程时点 | verifier 核对 |
| --- | --- |
| claim 成功返回 | 计划保留，零步骤 |
| prepare 成功返回 | prepared 步骤保留，result 仍为 nil |
| recordResult 成功返回 | succeeded 结果保留 |
| finish 成功返回 | 不在未完成查询中，plan ID 与 nonce 仍不可重用 |
| 未提交事务的脏页刷入数据库 | hot journal 恢复，未提交状态不会成为可见状态，原有 claim 保留 |

每个 verifier 都分别尝试重用 plan ID、重用 nonce，要求明确 `JournalError.replay`；恢复查询前后的数据相同，不续跑、不补偿、不把 prepared 标记为完成。再使用尚未占用的 ID / nonce 成功 claim，验证拒绝重放未错误消耗新标识。

未提交案例先写入并提交 10,000 条测试 seed 记录（finished），开启事务更新为未完成并变更 digest，然后调用公开 `sqlite3_db_cacheflush`。仅在 rollback journal 大于 512 字节且头部为 SQLite hot-journal magic 后才报告 ready。新 verifier 只能观察到原有一个未完成计划，seed 的未提交变化被回滚。此夹具直接使用系统 SQLite 制造存储故障状态；其他四个案例写入全部经由库公共 API。

SQLite 的公开 [db_cacheflush 接口](https://www.sqlite.org/c3ref/db_cacheflush.html)用于在事务中刷新可刷出的脏页；[原子提交说明](https://www.sqlite.org/atomiccommit.html)解释 journal 和恢复机制。测试检查实际 journal 内容，不将一个存在但头部全零的文件算作 hot-journal 证据。

## 实际执行结果

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePersistence
```

最终 13:20 的运行：构建成功；Swift Testing 报告 16 个测试通过，其中新参数化测试含 5 个案例，测试运行 0.661 秒，无跳过。原有 15 个测试也通过。

开发中的失败已修正：初次测试定位不到新 Xcode SwiftPM 布局下的辅助 executable，改用测试 bundle 锚点定位同级工具；Foundation 对已存在临时目录的别名规范化产生 `/tmp`，移除辅助工具冗余的字符串规范化判断，仍由库逐级 `openat/O_NOFOLLOW` 验证存储；仅缩小 cache 不能可靠证明 hot journal，改为显式 cache flush 并验证 magic。没有为使测试通过削弱 TransactionJournal 的存储检查，也没有改动其实现。

## 尚未证明

SIGKILL 是进程突然退出，不是物理断电、内核崩溃、磁盘写故障、介质回滚或攻击者回滚数据库。未使用故障注入 VFS 枚举每一个 SQLite 写入时点；未验证系统 mutation 与 journal 间的跨系统事务。prepared 只能表示上次执行结果可能未知，接入时仍须只读复核并经新计划处理，不可自动重放原动作。
