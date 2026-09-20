# 固定自有夹具实验持久日志

日期：2026-09-20。范围为 ResiduePersistence 的独立实验模型、独立 SQLite
存储和临时夹具测试；本报告不把包测试计为真实 VM 文件或 runtime 集成测试。

## 边界与接口

`OwnedFixtureExperimentJournal(directoryFD:createNew:readOnly:)` 仅在调用者已打开的
私有 0700 目录内访问固定 `owned-fixture-experiment.sqlite`。这是记录接口，不验证
调用者正在 VM 中，也不授予任何文件/服务操作权限。公开值即使由调用者自行构造，
仍只能记录；没有任意命令、操作执行器、GUI入口、Core VerifiedTransactionPlan转换
或导入报告转执行路径。原 journal.sqlite schema1/schema2 和 nonce 语义未更改。

独立数据库 application_id=1380403781、user_version=1，拒绝未知 schema、额外
表或列形状变化；正常打开缺失文件不会创建。`createNew` 只显式首次创建且拒绝覆盖。
`create(plan:)` 保存不可变计划；`prepare(planID:phase:backup:at:)` 提交后调用者才能
考虑固定实验动作；`recordResult` 留存结果，`entries` 只读解释。没有续做、重试或
恢复执行按钮/方法，prepared 没有 result 表示动作结果未知。

计划固定 ISO01 profile、Label、相对配置和程序位置；包含 planID、当前非root UID、
26A428 build、最长1小时有效期、完整源/程序 fingerprint（含有界扩展属性）、源目录
身份和隔离根身份。隔离与复原是预先规定的两个步骤。每一步保存 backupID/planID、
root UUID/目录名/父及根 dev+inode+owner、content/metadata/manifest SHA256 和
观察时间。metadata 摘要必须对应计划完整源 fingerprint 的 sorted-key JSON，
content 摘要必须对应源内容；backup 根名称必须匹配固定前缀和 root UUID。
源/隔离根及backup根设备须一致；源/程序须为无group/world写权限的普通文件。

复原 prepare 需要隔离结果为 quarantinedVerified 且 runtime 观察为
registeredNotRunning；pending、notMoved、movedUnverified、unknown runtime 均阻断。
复原证据允许重新观察时间变化，但稳定 backup 绑定必须相同，观察时间须单调，
且每步 prepare 时证据不超过120秒。计划有效期限制 prepare，不限制事后结果保存
或只读重开。verified结果必须提供对应sourceObject/quarantineObject，另一位置须为nil；对象的dev/inode/owner/group/mode/size/hash/mtime/xattrs须匹配计划源，允许rename导致ctime变化并保留观察。unverified/notMoved结果可省略对象或保留不同对象，不编造身份。

runtime 当前只保存 typed 结论，尚没有完整 collector generation/profile/exit/
coverage provenance；registration/permission 固定 noMutation，不声称卸载过服务。
备份证据是历史观察，日志不重新验证备份文件现在仍存在、内容有效或 runtime 当前状态。
Envelope 内容 hash 仅检查完整性，不是认证；能重写内容并重算 hash 的进程不因此可信。

## 存储和中断

目录 fd 复制并验证真实路径与inode，祖先 nofollow、权限/owner检查，最终私有目录
0700/no ACL；不因祖先正常 Library ACL 或 UF_HIDDEN 自动拒绝。数据库0600、单链接、
普通文件、无ACL；sidecar只接受同类安全 rollback journal，拒绝wal/shm。
SQLite事务采用DELETE/FULL/fullfsync；commit或commit后核查不确定会毒化当前连接，
调用者必须重新观察，不能凭异常认定动作未发生。最多128实验、单envelope128KiB、
累计payload8MiB、数据库/sidecar16MiB；扩展属性每值16KiB、共32KiB，比Backup支持
范围更保守，超限显式拒绝而不截断。

`readOnly:true` 使用O_RDONLY、SQLITE_OPEN_READONLY、query_only，不切换journal_mode，
拒绝create和写方法。需要hot-journal恢复时严格只读打开失败，不偷偷修复；显式writer
打开可执行SQLite自身回滚恢复，但绝不重新执行实验文件动作。清洁关闭后的只读重开
可读取完整材料。后续系统恢复必须另外核验源/隔离/备份/runtime，而非信任历史结果。

## 实际验证

环境：固定 `/Applications/Xcode.app/Contents/Developer`，项目 Swift 6/macOS
工具链。命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePersistence
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --package-path Packages/ResiduePersistence
```

Swift tests：**37 tests通过，0失败/跳过，0.561秒**，含原27项测试回归、新增10项实验
测试；参数化项分别包含失败/未知runtime3种、损坏/未知schema4种、绑定6种、links及
root mode/FIFO4种。验证完整证据重开、prepare/result顺序、plan及metadata/root绑定、
过期prepare拒绝而过期result留证、重新观察backup、严格只读写拒绝、缺失不创建、
权限、链接和FIFO（只读打开不阻塞）拒绝、损坏/未知版本及资源上限拒绝，verified缺失/换inode观测拒绝而unverified保留差异。

`killedWriterRecoversInIndependentVerifier` 现在包含 **18 crash参数cases**：原13个
legacy/schema2 cases不变，新增owned-created、owned-prepared、owned-result、
owned-prepare-beforecommit、owned-result-beforecommit。每例启动独立writer进程，
由父测试SIGKILL，再启动独立verifier进程。两个beforecommit cases经SQLite cacheflush
并核验hot rollback journal魔数后kill；verifier首先strict-readonly打开被拒绝并确认
hot journal字节未改变，再以writer连接执行SQLite回滚恢复，验证未提交状态消失而
先前已提交证据保持。所有测试只访问随机/private/tmp自有目录，无系统服务、备份
或隔离真实文件动作。不等同断电测试，也不证明恢复对象现在仍然有效。

初次新测试开发修复了async #expect漏await、Darwin.open与fixture方法同名遮蔽；
一次未固定DEVELOPER_DIR的CLT构建遇TestingMacros插件缺失，改用项目固定Xcode后
完成上述通过结果。未以跳过掩盖失败。

最终Release package build通过（6.03秒）；DEBUG crash checkpoint不进入Release。

## 后续：有界 runtime 历史 provenance

新增可选 `OwnedFixtureExperimentEffects.runtimeEvidence`，记录 generation UUID、
providerID、scope、Label、OS build、parser profile、观察时间、stdout SHA256、
exit code、capture failure、outputTruncated、coverage 和 state；不存原始输出或路径。
有证据的 observedRegisteredNotRunning 必须绑定固定 ISO01 Label/当前计划UID、
26A428/profile、exit0/none/未截断/completeWithinDeclaredScope/registeredNotRunning。
观察须位于该步骤prepare与result时间之间，并距result不超过120秒；历史读取不与
现在比较。unknown效果仍可保留有界失败/运行观察，永不因此升级或允许后续复原。

旧envelope省略runtimeEvidence字段仍可按原canonical字节读取，nil只代表旧typed结论
没有完整provenance；不补写、推断或伪造缺失证据，不改变schema/nonce。上述早期
runtime仅typed限制现在准确适用于nil记录；新有证据记录也只是历史观察而非认证。

实际回归：同一固定Xcode命令 **41 tests通过，0失败/跳过，0.456秒**，仍包含18个
独立进程crash cases。新增4项测试：完整往返及旧缺失兼容；15个known字段/时间
不一致拒绝；unknown超时/截断证据留存且不升级；unknown证据的3种未知枚举和超长profile拒绝。Release build再次通过（6.71秒）。GUI/Probe桥接不属于本包测试结果。
