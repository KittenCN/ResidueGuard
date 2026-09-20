# 只读恢复检查验证（2026-09-20）

本轮选择明确允许的安全回退：现有Backup固定VM probe仅返回脱敏字符串，Quarantine无法取得受信receipt和锚定Backup实例。为避免临时开放任意fd/路径入口而扩宽安全边界，本轮未新增VM移动入口，改为完成可独立测试的只读RecoveryInspection。没有更改生产gate、Xcode、Core、Backup或任何真实用户源。

代码位于 `Packages/ResidueQuarantine/Sources/ResidueQuarantine/RecoveryInspection.swift` 和 `QuarantineStore.inspectRecovery`。只读检查plan UUID、receipt版本与基名、源/隔离根、可信备份，顺序观察两个绑定名称，再核验目录和备份。区分原源存在、隔离待恢复、两处缺失、冲突、未知、无效备份、存储不安全及跨卷；不自动重试、移动、删除或补偿。

`permitsMutation=false`、`runtimeInspected=false`为不可变常量。`restoreCandidateRequiresNewPlan`仅为后续新的恢复计划输入。原源匹配不能证明曾完成恢复；允许ctime变化不代表忽略inode、mode、mtime、hash或xattr。

实际运行：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueQuarantine`。macOS27.0（26A428）arm64 / Xcode27.0（27A266a），2026-09-20 13:53，共30项XCTest，0失败。

新增10项覆盖：原源检查无移动/无授权、隔离物只产生候选、恢复后ctime变化、错误计划、两处缺失且不复制备份、双位置冲突、源dangling symlink、manifest篡改、不安全隔离根、隔离物ACL导致unknown。全部使用测试创建的随机临时自有目录。此前20项隔离/恢复测试继续通过。

限制：不是原子跨对象快照；没有验证运行服务、软件重新安装、计划时效或实际影响；没有接持久重启流程；跨卷真实实验仍notRun；不把当前对象存在状态当作操作历史。下一任务是固定VM受限lab context与持久receipt绑定设计，再把此检查用于启动后的只读复核。
