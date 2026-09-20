# 独立子进程 SIGKILL 与只读重开实验

新增 DEBUG-only `ResidueOwnedFixtureCrashProbe`、固定临时实验 context 与同包 runner。CLI 仅接受五种 checkpoint 名或 verify，以及规范 UUID；目录固定为系统临时目录下 `ResidueGuard-owned-crash-UUID`。worker 以独占 mkdir 创建新 0700 根，已存在立即拒绝，不接受路径、命令或 fixture 程序参数，不执行任何 fixture。

父测试进程创建 token，启动自己的确切 child，最多等待 10 秒。child 在真实 backup、文件隔离/恢复与 SQLite prepare/result 边界 fsync 固定 marker 后暂停；父进程对该 PID 发 SIGKILL 并 wait/reap。随后另一个独立 verifier 进程只读重开日志，观察源/隔离对象与原计划的 inode、dev、内容 hash、权限、owner/group、size、mtime、xattrs（rename 后 ctime 可变）。所有检查均无自动恢复或补偿。

| SIGKILL 边界 | 只读日志 | 文件位置 |
| --- | --- | --- |
| isolation prepare 已提交 | 1 步 pending | 源 |
| isolation rename 已返回，result 未写 | 1 步 pending | 隔离 |
| isolation result 已提交 | 1 步 quarantinedVerified | 隔离 |
| restoration prepare 已提交 | 2 步，最后 pending | 隔离 |
| restoration rename 已返回，result 未写 | 2 步，最后 pending | 源 |

每例验证 verifier 前后所有 fixture/SQLite/marker 文件字节保持一致。额外负例放入明确合成的未解决 rollback sidecar；verifier 在 SQLite 打开前拒绝任何 journal/WAL/SHM sidecar，保持原字节，不尝试 hot-journal recovery。这并非真实数据库写事务中途断电测试，也不宣称此类介质故障已覆盖。

程序身份、runtime/build 在这些内部实验中是**合成历史输入**，JSON 标注 `syntheticRuntimeAndBuild=true`、`authorizesMutation=false`、`automaticRecovery=false`。这组用真实文件、真实 SQLite 和真实 SIGKILL 验证跨进程边界，不代表 launchd 服务、VM 门禁、生产确认或清理 gate 通过。测试结束仅删除父测试持有 token 的自有新根；没有读取/修改宿主真实 LaunchAgents。

Release 构建不包含 context/runner 实现；入口一律 exit 77。实测 `swift build --package-path Packages/ResidueBackup -c release --product ResidueOwnedFixtureCrashProbe` 成功，随后运行 Release binary 输出 DEBUG-only refusal、exit 77。测试只在 DEBUG 编译。

验证环境：macOS 27.0/26A428 arm64，Xcode 27.0/27A266a，固定 DEVELOPER_DIR。命令 `swift test --package-path Packages/ResidueBackup --filter OwnedFixtureCrashIntegrationTests`。日志 `.local-evidence/crash-integration.log`，Release 构建日志 `.local-evidence/crash-release-build.log`。本任务未运行 VM，不改原 VMProbe/QuarantineStore，不提交。

最终定向结果：2026-09-20 15:52:51，6 项、0 失败，exit 0，耗时 1.776 秒；`git diff --check` 通过。首次编译发现嵌套 Snapshot 类型需限定为 QuarantineStore.Snapshot，修正后上述实际测试通过；未把编译失败记为通过。
