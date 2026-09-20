# 固定实验根只读枚举

`OwnedFixtureAuditLabReader.read()` 是 package 级零参数入口，要求 VirtualMac、当前非 root uid/euid 相同、macOS 27.0.0 与 build 26A428。当前用户 home 来自 getpwuid，逐级 O_NOFOLLOW 打开固定 Library 与 LaunchAgents；没有调用者路径、其他用户访问、创建或恢复入口。

Library readdir 最多 4096 项，仅匹配 `ResidueGuard-VM-VerifiedBackup-` 加规范 UUID；最多检查 64 个匹配实验根（含被拒根）。结果分别记录枚举完整/目录项上限/实验根上限，以及拒绝根数量。根要求当前 uid、0700、flags=0、无 ACL；符号链接、替换、权限不符拒绝。父 Library 保留标准祖先策略，不修改它。

每个 root anchor 提供 `withDirectoryFD` 和 `revalidate`，固定 source anchor 提供 `withSourceDirectoryFD` 和 `revalidate`；source 允许安全 0755，拒绝非 owner 写、ACL 与 flags。FD 以 O_RDONLY 打开，但目录 O_RDONLY 不是操作系统级写入沙箱，接口仅供同包受信只读 journal/snapshot 代码。跨 await 读取调用方须再 revalidate。锚点校验不提供原子快照，不授予清理或恢复权限。

自有临时夹具测试覆盖限定名称只读枚举、unsafe/link 拒绝、替换拒绝、64 根上限、4096 项上限。真实 VM 枚举需主任务独立执行并记录，不能用临时测试替代。源anchor在真实入口必存在，internal临时枚举 seam不打开用户LaunchAgents，返回source=nil。

实际验证：固定 Xcode 的 `swift test --package-path Packages/ResidueBackup --filter OwnedFixtureAuditLabReaderTests`，2026-09-20 15:38:21，5 项、0 失败，exit 0（macOS 27.0/26A428 arm64、Xcode 27.0/27A266a）；日志 `.local-evidence/audit-reader-tests.log`。早先一次测试编译遇到同时开发的新 executable 尚未实现方法，未记为测试通过；完整实现到位后此次通过。

此外独立 `OwnedFixtureJournalIntegrationTests` 4 项在 15:34:23 通过：真实临时文件隔离/恢复结合 journal 的两步记录与只读重开，记录失败保留 pending 且不恢复，prepare 后取消不移动源，以及 restore prepare 失败保持隔离。该测试明确以合成的 profile/program/runtime 历史输入驱动内部 seam，不代表真实 VM 门禁或注册观察通过。

主任务补充：独立零参数ResidueOwnedFixtureAuditProbe在VM实际退出0，读取1条实验两步记录，source=matchesHistory、quarantined=absent；5个无journal早期目录独立计数，未当作空记录成功。backupFreshlyVerified/runtimeInspected/authorizesMutation均false。宿主门禁退出77、参数退出64。此为跨进程只读比较，非重启恢复/备份再认证。原始JSON仅保留本地证据。
