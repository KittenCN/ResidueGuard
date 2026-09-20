# 固定自有临时夹具的只读 fresh 恢复一致性检查

新增Backup模块内部 `TemporaryFreshRecoveryReader` 和 `FreshRecoveryAssessment`，只提供测试可见的fd注入初始化；无public路径/根目录工厂，无VM入口，无执行、确认或授权能力。没有接SyntheticRecovery合成hash模型，也没有导入历史审计后提升为可信收据。

## 实际复用与检查

复用VerifiedBackup既有 `readOpened` 有界读取：nofollow/nonblock打开、当前用户普通单链接文件、权限/flags/ACL检查、xattr、同一fd读前读后身份/时间/内容检查、文件名到fd身份重核。目录策略由新增模块内部wrapper复用原私有检查，不放宽原策略。

临时父fd为测试信任边界；固定子目录只有 `source`、`quarantine`、`backups`，源名固定 `example.residueguard.fixture.iso01.plist`。三目录打开后保存dev/inode，每次检查及完成前重新核对parent/name；隔离与backup目录要求0700，backup文件600。按内部UUID定位backup目录及隔离对象，拒绝跨卷。

原名必须通过nofollow查询得到ENOENT；任何存在对象包括dangling symlink均阻断。实际重读manifest、backup内容和隔离文件，核对backup/隔离bytes一致、manifest所记内容hash/size及隔离dev/inode/owner/group/mode/mtime/xattr一致。历史ctime因rename允许不同，但输出包含本次实际ctime，两次当前读取必须相等。另核对backup目录身份及manifest/content文件的当前完整指纹。plist只验证固定Label，没有启动payload。

manifest解码为独立私有 `UntrustedManifest`；没有构造BackupReceipt，没有调用prepare创建新备份，也没有填充issuedAuditReceipts。读取器内部VerifiedBackup实例仅用既有只读方法，不调用其prepare或receipt验证API。

## Manifest 新写格式与旧读兼容

审查后将 `VerifiedBackup.prepare` 新manifest输出改为JSONEncoder.sortedKeys；字段、日期语义、版本仍不变。新reader只接受解码后按同一编码规则重编码逐字节相等的实验规范格式；重复/未知字段、额外空白及其他非规范表达拒绝。这不是通用JSON规范化标准，也不是签名格式。

既有 `VerifiedBackup.verify` 仍按原语义解码，旧非规范manifest可以继续验证，不自动迁移任何旧文件。正向测试直接用真实prepare输出，然后rename测试自有文件，再fresh inspect，没有为了通过而重写manifest。专门负例验证旧格式仍被旧verify接受，但新reader拒绝。

## 输出与限制

输出固定 `historyTrust=untrustedHistory`、`permitsMutation=false`、`runtimeInspected=false`、`programInspected=false`、`fixturePolicyVerified=false`。输出hash和身份来自本次真实读取，但历史manifest仍可能被同UID重新编造；内容一致不证明历史来源可信。没有校验Program/ProgramArguments/RunAtLoad/KeepAlive、程序签名或真正VM门禁，因此不能称完整ISO01可恢复。

两次读取只提高发现变化的能力，不是原子文件系统快照，不能证明期间从未变化或返回后仍不变。顶层注入parent fd祖先未验证；真实VM必须另加固定home链/root定位。尚未实现新计划、真实两次用户确认、运行时检查、最后动作重核、持久化intent或恢复执行；rename竞争风险和第三方gate均未改变。

## 实际验证

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueBackup` 全包通过：Backup XCTest **54**、Quarantine XCTest **79**，以及本轮新增Swift Testing **11**项；总计144项，0失败。日志 `.local-evidence/fresh-recovery-full-tests.log`。不要把runner末尾另一个target的0项误计为未运行或额外通过。

新增测试覆盖真实prepare→隔离临时文件→fresh读取；源普通冲突/dangling symlink；backup/manifest/隔离内容篡改；软硬链接及不安全mode；三根路径替换；两次读取间manifest文件身份替换；backup目录替换但保留原文件；隔离元数据变化/错backupID；读取间源出现；重复/未知/非规范manifest；旧读兼容。所有文件位于测试随机创建的临时目录，测试结束只清理其自有根。

环境macOS27.0/26A428 arm64，Xcode27.0/27A266a。最终日志无warning/error，git diff --check通过。未运行VM、宿主真实LaunchAgents、GUI、服务命令或任何恢复动作。下一步是独立只读固定VM上下文与完整fixture程序/profile校验设计，不能直接把本reader结果转成执行token。
