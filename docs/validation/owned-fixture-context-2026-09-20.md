# 固定自有VM实验上下文（2026-09-20）

代码与临时夹具验证后，主任务已在既有可回滚VM执行固定ISO01实验；结果见本文末尾。

架构：把原`Packages/ResidueQuarantine`的源码/测试迁入`Packages/ResidueBackup`，仍提供独立`ResidueQuarantine` product/module。移除旧独立Package.swift及废弃生成build目录；`script/test.sh`按两个target过滤，避免命令入口失效。Core、Platform和App生产门不改变。

`OwnedFixtureLabContext`及其中fd/Backup实例仅为Swift package访问级别。复用原ISO01固定验证：真实VirtualMac、非root、passwd家目录、逐级nofollow目录验证、固定完整plist键集合/Label/ProgramArguments、RunAtLoad和KeepAlive必须false，固定fixture owner/mode/单链接/严格签名identifier。没有新public任意路径/fd构造器。仅公开零参数`QuarantineStore.runISO01VirtualMachineProbe()`及固定可执行入口。

`ResidueOwnedFixtureVMProbe`使用既有Platform只读collector，要求受测build/profile下registeredNotRunning，分别在备份前、隔离前后、恢复前后观察。流程为backup→isolate→readonly inspection→planned restore→readonly inspection；从不bootstrap/bootout/kickstart。服务未找到仍是unknown而不是不运行。成功只说明若干次观察到registeredNotRunning，不宣称登记历史没有任何变化。

任意runtime未知或文件核验失败停止。隔离后失败可能保留已隔离文件；返回phase/fileState/backupID，不自动恢复、删除或补偿。正常restore属于已指定自有实验步骤。没有完整journal、产品确认或交易token接线；不能开放第三方生产清理，也没有解决check→rename并发源替换限制。

实际命令与结果（macOS27.0/26A428、Xcode27.0/27A266a、arm64）：

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueBackup`：Backup17 + Quarantine38（原30 + 新流程8），均0失败。
- `.build/debug/ResidueOwnedFixtureVMProbe`：宿主exit77，明确拒绝VirtualMac之外运行。
- `.build/debug/ResidueBackupVMProbe`：提取上下文后的旧备份probe宿主仍exit77。
- `.build/debug/ResidueOwnedFixtureVMProbe unexpected`：exit64，不接受参数。

新8项流程测试验证正常往返的4个动作边界runtime检查、隔离前unknown保留原源、隔离后unknown不补偿、恢复前unknown不补偿、恢复后unknown如实报告已恢复文件状态、隔离unverified立即停止、出现新源时只读检查拒绝覆盖，以及恢复动作拒绝时不把已经隔离的整体实验误报notMoved。runtime返回为测试注入，不能代替客体launchctl验证；文件动作使用随机临时自有目录的真实文件API。

构建入口：`swift build --package-path Packages/ResidueBackup --product ResidueOwnedFixtureVMProbe`，二进制位于该package `.build/debug/ResidueOwnedFixtureVMProbe`。下一步在已授权自有VM夹具上独立运行并记录源/隔离/备份及runtime真实结果；若后置检查拒绝，先读取结果和保留证据，不自动重跑或恢复。

## 后续真实客体验证

同一macOS27/26A428 VirtualMac客体，将新probe复制到独立客体目录，先核对SHA256和strict签名后执行；真实退出0，返回 `PASS ISO01 backup/isolate/inspect/restore verified`。文件backup→isolate→inspect→restore→inspect由实际fd API执行，各次runtime观察均为registeredNotRunning，未执行注册变更命令。成功输出和退出码保存在忽略的VM transfer evidence目录，截图也直接观察到PASS。

这完成固定自有夹具正常路径；不等于完整产品事务、第三方清理、崩溃恢复或磁盘满矩阵。仍保留check→rename竞争限制和生产gate关闭。没有启动夹具程序，也未改变RunAtLoad/KeepAlive。
