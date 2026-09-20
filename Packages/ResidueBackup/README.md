# ResidueBackup：备份验证原型

独立 Swift 6 / macOS 14+ package，当前没有公开构造器，没有 GUI 或生产 LaunchAgents 入口，不接执行器，不改变 production gate。`@testable` 测试能注入已打开的自有私有目录 fd；另有无参数、仅 VirtualMac 的固定 ISO01 实验入口。未来生产工厂必须逐级验证当前用户固定允许根及备份根；这部分尚未实现，不能把原型当成已完成的清理安全门。

已实现：以复制持有的目录 fd 为锚，单文件 `.plist` 基名（无路径/空字节）经 `openat(O_NOFOLLOW|O_NONBLOCK)` 读取。拒绝非普通文件、非当前用户所有、hardlink、不安全写权限、特殊 mode/flags；读取有 1 MiB 上限，前后核对 device/inode/uid/gid/mode/size/mtime/ctime/hash，并核对目录中的当前名称仍指向相同对象。源目录必须当前用户所有、无组/其他写权限、无 ACL；备份目录另要求0700。

源文件扩展属性通过公开 fd API 有界读取，按原始字节完整保存在 manifest 的 fingerprint 中（名称总长 64 KiB、单值 64 KiB、值总量 128 KiB），读取失败/不合法名称/超限/前后变化均拒绝。并未将这些属性安装到备份内容文件；未来恢复需要单独验证和应用。源文件或备份目录/文件存在 ACL 时拒绝，绝不悄悄丢弃 ACL；没有恢复接口。测试发现系统自动附加 provenance 属性，因此实现实际元数据保存，而非移除或忽略它。

每次生成独立 UUID/0700 子目录；内容和 manifest 通过 `O_EXCL` 以0600写入，完成 `fsync` 文件和目录后读回校验，再次核验源文件。manifest 绑定计划 UUID、源基名、身份/内容/属性和时间，服务状态固定 `notInspected`。任何失败都不会返回成功 receipt；可能留下私有不完整目录用于诊断，不自动删除或尝试系统补偿。

`verify(receipt)` 必须拿受信调用方保存的 receipt 校验；目录内 manifest 本身不能成为授权依据。同 UID 已获完全控制的进程、断电时存储设备写缓存、恶意并发的穷尽竞争、跨卷恢复、原路径逐级解析、owner/group/xattr 重新应用、服务状态和权限恢复均未得到此模块保证。`fsync` 不是对突然掉电的完备承诺。`ResidueBackup`模块没有删除、隔离、恢复、shell执行或服务操作API；同包另有隔离模块，边界见[隔离文档](QUARANTINE.md)。

测试只创建随机临时根，文件写入、ACL修改和清理都只针对本次创建的夹具，不访问真实 LaunchAgents。运行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueBackup
```

## 固定 VM 实验入口

`swift build --package-path Packages/ResidueBackup --product ResidueBackupVMProbe` 生成 `.build/debug/ResidueBackupVMProbe`。不接受参数、路径或环境授权绕过；真实 `sysctl(hw.model)` 非 VirtualMac 或 root 直接 exit77，参数 exit64，验证失败 exit65。先从 `getpwuid` 获取当前用户家目录，逐级 `openat(O_NOFOLLOW)` 验证根到家目录、Library 和 LaunchAgents，祖先 ACL 只接受 deny 条目，不通过修改源目录权限来使验证成功。

唯一源是已由 ISO01 harness 安装的 `example.residueguard.fixture.iso01.plist`，要求固定完整键集合、Label、当前用户固定 fixture 路径、两个false布尔字段；固定 fixture 本身要求当前uid单链接0700普通文件及严格代码签名校验、对应identifier。ad-hoc identifier 不构成抵御同UID恶意伪装的身份保证，此入口只用于现有自有实验。备份目的地由执行端在 Library 下新建 `ResidueGuard-VM-VerifiedBackup-UUID` 私有根，内部仍为UUID备份目录。成功仅输出脱敏结果和随机backupID，未输出用户路径、内容或xattr。不会修改源、执行fixture、调用launchctl或调整生产能力。VM真实执行结果由单独验收补记。

## 同包受限实验上下文

`ResidueQuarantine` product/target及其测试已迁入本package，原独立package不再保留。`OwnedFixtureLabContext`和描述符/备份实例只用Swift `package`访问级别共享，不是public API；公开入口只接受零参数固定ISO01实验。通用Backup/Quarantine构造器仍不公开，没有任意路径或fd工厂。

`swift test --package-path Packages/ResidueBackup`运行两个测试target；`script/test.sh backup`只筛选32项备份测试，`script/test.sh quarantine`筛选38项隔离/只读恢复/流程测试。

新`ResidueOwnedFixtureVMProbe`构建后由独立VM验收任务运行。它复用同一硬件/用户/固定源/签名验证，另用已验证profile的只读collector要求registeredNotRunning，在备份前、隔离前后、恢复前后观察。它不会bootstrap/bootout/kickstart，也不把未找到服务当作不运行。错误时只输出phase/fileState/backupID并停止，无自动补偿。详见[隔离文档](QUARANTINE.md)。

## package级真实备份审计证据桥

`inspectAuditEvidence(receipt:)`只对已绑定根、且由当前store实际`prepare`签发并记住身份的receipt返回`BackupAuditEvidence`。类型与方法均为package级，证据无public/Decodable构造器，`authorizesMutation`固定false；没有新增恢复、执行或schema写入接口。

返回实际读到的manifest字节SHA256、备份内容SHA256、源fingerprint的sorted-keys JSON SHA256（格式标识`source-fingerprint-json-sorted-keys-v1`）、backupID/planID和受限根定位。元数据hash包含源fingerprint全部字段及xattr，不是“元数据已经恢复”的声明。固定VM locator由已验证Context生成labUUID，绑定父目录/根目录device+inode和owner；检查时再次核验固定父路径、父fd和根名称。临时测试使用独立`temporaryFixture`命名空间。

`prepare`在根已绑定时记住备份子目录、manifest和内容文件的身份/指纹，检查桥拒绝内容相同但inode替换。每实例最多保留64份签发记录；新prepare超限拒绝，不删除旧备份。二次锚定读取与根复核仍不是原子跨文件快照。根内新增无关quarantine子目录不会因目录ctime改变误拒绝，但根身份、权限或名称被替换会拒绝。

证据只是新鲜的备份观察，既不验证源当前位置/运行服务，也不验证计划有效期/用户确认。包访问级别是代码封装边界，不是抵御同UID完全控制的认证。重启后新store即使能读取并verify原manifest，也不能签发此进程内证据；历史重建仍需要独立受信持久绑定设计，不能把导入JSON当作原始签发。

新增15项临时夹具测试后，Backup32 + Quarantine38通过。本轮未执行VM，未把该证据桥接入Persistence/Core。专项记录见 `docs/validation/backup-audit-evidence-2026-09-20.md`。

审计父锚点与备份对象使用不同 ACL 策略：标准 Library 的非继承 `deny delete` 可接受；allow、其他 deny 权限或继承 entry 被拒绝。备份根和备份文件仍完全拒绝 ACL；代码不会为了通过检查修改真实 Library ACL。
父锚点仅允许 Finder 的 UF_HIDDEN 标志，其他 flags 拒绝；备份根和备份文件仍要求 flags=0。临时目录回归覆盖父目录 hidden + deny delete 的标准组合，不修改实际 Library。
