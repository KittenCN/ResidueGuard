# 固定 Bootout 实验只读审计探针

新增零参数 `ResidueOwnedFixtureBootoutAuditProbe`，由独立进程只读重开实验记录，不启动 launchctl、不执行 source/服务修改，不产生授权。复用现有 OwnedFixtureAuditLabReader 的真实 VirtualMac/current nonroot UID/macOS 27.0.0 / 26A428 门禁、固定当前账户 Library 根、安全目录锚点、4096 个目录项与 64 个实验根上限；未改原 reader。既有 reader 同时要求 LaunchAgents source anchor 可访问，本探针保留此保守前提。

每个根只打开固定 intent JSON 有界发现 untrusted attempt UUID，再调用 OwnedBootoutLog(readOnly:true).readAll 验证 canonical envelope、摘要、attempt/slot 关联、目录/文件身份与元数据。发现到 attempt 不代表验证成功。缺少 intent 但存在后续槽是 failedLog；完整 intent 无 outcome 是 pendingOutcomeUnknown。全部失败以 partial 与计数展示，不能冒充成功空列表。

输出只有 attempt、固定槽名、已记录 outcome、mayHaveExecuted、postFileMatchesHistory，以及 command/post 两组 capture 汇总：exitCode、failure、outputTruncated、launched、原始捕获摘要和 emptyCapture/unparsedDiagnostic 分类。摘要必须是 64 位小写十六进制，拒绝伪造为路径的字符串；不输出 stdout/stderr、home、source/program 路径。emptyCapture 不代表服务缺失；postRuntime 永远 unknown，absenceProven=false，freshFilesInspected=false。postFileMatchesHistory 是旧观察，不是此次重新检查文件。

本轮仅新增 reader/CLI/tests、Package target 与此文档，未修改正在 VM 使用的 Bootout mutation/log/transport。主任务已报告 VM bootout-v1 exit0、文件未变、后置unknown；独立 reader 的真实 VM 结果尚待主任务运行，不能以本轮纯测试替代。

实际验证（固定 Xcode）：

- `swift test --package-path Packages/ResidueBackup --filter OwnedFixtureBootoutAuditTests`：4 项通过。覆盖 absent/pending 区分与无新文件/原文不变、历史unknown/摘要脱敏、孤立槽/不一致outcome拒绝、失败capture保真/不安全摘要拒绝。
- `swift build --package-path Packages/ResidueBackup -c release --product ResidueOwnedFixtureBootoutAuditProbe`：通过。
- 宿主 release 零参数只触发环境拒绝 exit77；传 --help exit64；未扫描 VM/宿主实验根。
- `git diff --check` 通过。

release 路径：`Packages/ResidueBackup/.build/out/Products/Release/ResidueOwnedFixtureBootoutAuditProbe`。可由主任务复制到 VM 本地新目录，零参数运行并私有保存 JSON。无恢复、重试或 service 启动入口。

## 真实 VM 独立进程结果

主任务完成 bootout-v1 后，在相同专用 VM 运行本 reader；本轮读取已导出的本地结果与退出码。exit0，coverage=complete，1 个实验、4 个槽，failedLogs=0、refusedRoots=0、logsAbsent=8。command exit0；post print exit113，仍为 unknown / absenceProven=false，没有把非零退出当成未注册。freshFilesInspected=false；文件匹配值仅是先前 probe 记录的观察。独立进程成功重开是历史记录验收，不是新一次系统清理或运行时验证。

最终完整验证：固定 Xcode 执行 `swift test --package-path Packages/ResidueBackup --filter ResidueQuarantineTests`，**76 项通过**。本轮仅读取证据、测试、回写文档，没有新 VM 操作。

## 下一步 SIGKILL 实验设计（仅设计，未新增代码）

复用现有 DEBUG-only `ResidueOwnedFixtureCrashProbe` 的固定 phase + canonical UUID 参数协议、OwnedFixtureCrashContext 随机临时目录、安全 fd、durable checkpoint 及独立 verify 子进程；增加独立 bootout-log 场景命名，与现有文件隔离/恢复阶段分离。**不调用 OwnedBootoutTransport，也不调用真实 VM bootout 入口**：使用 OwnedBootoutSequence 的内部注入结果，只测试日志崩溃语义，runtime/build 均标记 synthetic。

最小三个阶段：

1. `bootoutAfterIntent`：OwnedBootoutLog 的 intent append 完成所有同步持久化后，由测试 hook 写固定 checkpoint 并 pause；父进程仅 SIGKILL 此 worker。第二进程只读重开，应只有 intent、pendingOutcomeUnknown、mayHaveExecuted=unknown，绝不根据测试预知“未发出”把一般持久记录推为 false。
2. `bootoutBeforeOutcome`：fake issue 返回 launched=true 后、record outcome 前 checkpoint；SIGKILL 后与阶段一同样 pending/unknown。这验证已发出但缺 outcome 的歧义，不能证明真实 launchd 的行为。
3. `bootoutAfterOutcome`：fake issued outcome durable append 后 checkpoint；SIGKILL 后独立读取有 intent/outcome，记录已发出以及固定合成退出/失败，post observation 缺失，仍 unknown，不自动补查或重试。

父进程复用已有10秒有界checkpoint等待、确认它创建的worker尚活着且token/phase匹配、仅杀自己的PID、wait收尸，再启动独立只读 verify。每阶段使用新随机token，测试后仅移除该临时根；不碰宿主 LaunchAgents、实际程序或系统服务。verify 必须调用真实 OwnedBootoutLog(readOnly:true) / OwnedBootoutAuditReader，比较文件名称/内容摘要未变、无新文件，不运行恢复。

如需验证 outcome 文件写到一半时的 torn record，再单独增加 DEBUG 文件写入中 checkpoint：读取应 failedLog/未知，而不是回退为旧成功；该项不必混入首批三个持久边界测试。现有 append 成功返回后的 checkpoint 不能声称覆盖“写中断”。真正 bootout 发送中的 SIGKILL 是另一个有副作用 VM 实验，需要受控快照与单独阶段安排，不由上述宿主 synthetic 测试替代。
