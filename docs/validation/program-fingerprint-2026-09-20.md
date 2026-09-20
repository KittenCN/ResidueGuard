# 固定 ISO01 程序身份补齐

`OwnedFixtureLabContext.programFingerprint` 为 package 只读 `SourceFingerprint`，包括 SHA-256、device/inode、uid/gid、mode、size、mtime/ctime 与有界 xattr 原值。没有新增 public 构造器、调用者路径参数或程序启动能力。

固定工厂保留原有签名 identifier 与严格签名有效性检查。签名前后使用同一个已打开的固定 `fixture` fd 获取并比较完整指纹；每次读取同时核对目录锚定名称仍指向同一 inode。程序必须当前用户所有、0700、单硬链接、无 flags/ACL；有界大小沿用 1 MiB。签名 API 仍按固定路径检查，前后文件身份/内容检查缩小替换窗口，不承诺对完全控制同 uid 的对手建立原子签名与文件系统快照。

为避免复制底层安全逻辑，将 VerifiedBackup 原读取实现抽为 module-internal `readOpened`，原有调用也委托该实现。采用 pread，不消费共享 fd 偏移量；没有向其他 package target 暴露 raw fd 读取接口。

新增 6 项自有随机临时夹具测试：内容/metadata/xattrs 与重复读取、程序变更拒绝、名称被替换拒绝、超过 1 MiB 拒绝、权限变化拒绝、名称符号链接替换拒绝。夹具字节从未执行，未修改真实用户软件。

实际执行：固定 Xcode DEVELOPER_DIR 的 `swift test --package-path Packages/ResidueBackup --filter ResidueBackupTests`，2026-09-20 15:27:19，46 项、0 失败，exit 0；macOS 27.0/26A428 arm64、Xcode 27.0/27A266a。日志 `.local-evidence/program-fingerprint.log`。`git diff --check` 通过。本任务未运行 VM，未声称持久实验日志或生产清理已完成；下一步由调用层把该真实身份绑定到实验计划与审计记录。

## await 后再次核验

新增 `package func verifyProgram() throws`，不创建新的实验目录。与 create 共用固定程序核验 helper：从 `/` 逐级 O_NOFOLLOW 重开既有 home/Library、固定私有 fixture 根与程序，再进行严格签名 identifier 核验、同 fd 签名前后全指纹比较、与 context 原 programFingerprint 比较，并重开路径核对 fixture 根 dev/inode。调用方可在日志 prepare await 后再次调用；这不替代源文件与 runtime 的独立 fresh check，也不消除最终检查至操作间所有并发窗口。

新增真实临时 Mach-O 副本的 ad-hoc 签名测试：正确 identifier 可以重复核验，篡改内容同时被旧指纹和重新签名检查拒绝，错误 identifier 拒绝，未签名内容拒绝。只读复制系统程序到自有随机临时目录后签名，从未运行程序，未改系统原件。

追加验证同一 Backup filter 命令：2026-09-20 15:30:10，49 项、0 失败、exit 0，日志 `.local-evidence/program-revalidation.log`。没有在本任务运行 VM。
