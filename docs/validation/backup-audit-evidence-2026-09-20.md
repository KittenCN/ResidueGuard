# 真实备份审计证据桥（2026-09-20）

初始包级实现仅修改 `Packages/ResidueBackup`；没有修改Core/Persistence/schema、操作服务或开放生产gate。后续主任务接入固定 probe 并运行 VM，结果见末节。新增package级`BackupAuditEvidence`、受限root locator及`VerifiedBackup.inspectAuditEvidence(receipt:)`，为后续审计接线提供实际验证证据，不提供新恢复/执行接口。

## 验证行为

固定VM Context在验证既有ISO01来源和签名后绑定其生成的labUUID、Library父fd与私有root。root locator包含命名空间、生成的目录basename、rootID、父/根device+inode、owner；不是任意绝对路径。证据检查重新遍历固定父路径并确认仍对应同一父fd，再核验其下名称与根fd身份。内部临时fixture绑定单独标识`temporaryFixture`，不能被误称VM观察。

仅根已绑定时，prepare保存当前实例真正签发的receipt及备份目录/两个文件身份。桥先核对该记录，再以fd锚定重新读取两次，核验实际manifest内容等于原receipt，备份内容等于原源hash，以及目录/文件身份和元数据。读取后再次核验root绑定。返回值包括backupID、planID、实际manifest字节hash、实际内容hash、完整源fingerprint规范编码hash与观察时间。所有hash均来自实际已验证内容，没有占位hash。

元数据编码明确为`source-fingerprint-json-sorted-keys-v1`：SourceFingerprint全部字段（含xattr和源内容hash），JSONEncoder sortedKeys。manifest hash取实际文件字节，绝不通过重新编码receipt冒充。manifest或内容文件即使替换成相同字节，只要inode/指纹不同，也不能取得证据。

证据类型与方法为package级，没有public或Decodable证据构造器，`authorizesMutation=false`。签发记录只保存在当前store实例内，最多64份；新实例读取旧manifest不能自动获得历史签发身份。这不解决同UID完全控制者认证问题，也不意味着未来不需要持久恢复绑定。

## 实际测试

命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueBackup`。

环境：macOS27.0/26A428、Xcode27.0/27A266a、arm64。新增15项桥测试，加原17项备份测试=Backup32；Quarantine38回归。均使用随机临时自有目录。

覆盖：真实manifest/content/meta hash及根绑定、篡改planID、其他store导入receipt拒绝、相同字节换manifest inode、相同字节换内容inode、manifest symlink、内容hardlink、根替换、根symlink、备份子目录替换、xattr变化、未绑定root、正常新增quarantine兄弟目录、内容篡改、根权限变宽。

限制：顺序读回不是原子文件系统快照；未验证源当前存在状态、runtime、计划有效期或用户确认；未接journal的prepare/result序列；未实现重启历史receipt恢复；包级测试不代表VM验证，后续结果见末节。包封装不等于安全认证，也没有解决源check→rename竞争。

下一最小任务：在保持生产gate关闭的情况下新增独立ownedFixtureExperiment审计计划语义，准确表示隔离/只读检查/恢复，不能用假bootout或synthetic确认凑现有schema2调用。然后将这里的真实证据通过typed适配绑定到新的历史envelope，并做prepare/rename/result崩溃边界测试。

## VM 首次桥接失败与父锚点 ACL 修复

首次带真实证据桥的 VM probe 返回 exit 65，输出 `fixed ISO01 validation or backup failed; no automatic compensation`，不能记为通过。随后客体只读诊断显示 `Library` 当前用户拥有、0700，但具有标准 `group:everyone deny delete` ACL。新增绑定曾错误复用备份目标的完全无 ACL 策略，因而在创建实验上下文时拒绝父目录。

修复将父锚点与备份对象策略分开：父目录仍要求当前 uid、不可 group/other 写、无特殊 mode/文件 flags，仅接受无 ACL 或每条 entry 都是 deny、权限 mask 精确等于 delete、无已知继承/控制 flags 的 ACL；其他权限、allow 或继承 entry 拒绝。每次证据验证重新检查这一策略及原有 fd/名称/dev/inode 定位。备份根、子目录、manifest、内容文件继续要求无 ACL，不改变真实 Library 权限。

在随机自有临时目录实际调用系统 chmod 设置 ACL 的 5 项新增回归覆盖上述接受/拒绝边界，包括带标准 ACL 的初次绑定、prepare、证据重读，以及验证时新增 allow 后拒绝。定向 `swift test --package-path Packages/ResidueBackup --filter BackupAuditEvidenceTests` 实测 20 项、0 失败（2026-09-20 14:59:42，macOS 27.0/26A428 arm64，Xcode 27.0/27A266a，固定 DEVELOPER_DIR）。这轮修复的真实 VM 重跑由主任务另行记录，不能用临时目录测试替代。

随后同包完整 `swift test --package-path Packages/ResidueBackup` exit 0：Backup 37 + Quarantine 38 = 75 项，0 失败；日志 `.local-evidence/backup-audit-acl-full.log`。SwiftPM 分 test product 输出统计，不应把某个过滤为空的独立 bundle 尾部 0 tests 当成整个测试命令未运行测试。

## 第二次 VM 拒绝：父目录 Finder hidden flag

只修 ACL 的 v3 probe 仍在进入带阶段捕获前返回 exit 65，仍是失败。客体追加 `stat` 与 `ls -ldeO` 诊断实证父 Library mode=0700、当前 uid、flags=32768（UF_HIDDEN），同时存在标准 deny delete。新增父策略要求 flags 全零，是第二个把备份对象策略错误施加到标准祖先目录的约束。

父锚点现仅允许 UF_HIDDEN 位，任何其余 flags 位仍拒绝；备份根及所有备份文件仍必须 flags=0。未修改客体 Library、源文件或源服务。新增真实 chflags 临时夹具测试：父目录 UF_HIDDEN + deny delete 的实际组合可绑定/prepare/重读；备份根 UF_HIDDEN 拒绝；父目录 UF_HIDDEN | UF_NODUMP 拒绝。分阶段脱敏诊断由主任务维护 probe，单独记录；本修复不扩大生产 gate。

此版本完整 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueBackup` exit 0：Backup 40 + Quarantine 38 = 78 项、0 失败（含加强后的组合正例）；日志 `.local-evidence/backup-audit-flags-full.log`。实际 VM 新版重跑结果待主任务，不能据此宣称修复后 VM 已通过。

## 主任务 VM 接入验证

固定零参数 probe 已在隔离前、恢复后分别调用证据桥，比较 backupID/planID/root及实际三类hash；任一失败停止，恢复后的失败明确保留restoredVerified文件状态。新增createContext/backupPreparation/quarantinePreparation阶段及固定错误枚举，避免泛化失败掩盖具体阶段；不输出任意异常路径。宿主调用实际exit77，参数调用exit64。

VM先后两次exit65，分别暴露父Library的标准deny delete ACL与UF_HIDDEN标志。代码修复仅父锚点允许非继承精确deny delete和UF_HIDDEN，私有备份根/文件仍禁止ACL与flags；未修改客体Library权限。新增实际chmod/chflags测试后Backup40 + Quarantine38通过。

修复后的Release probe实际在macOS27/26A428 VirtualMac运行退出0：`backupAuditEvidence=verifiedBeforeAndAfter`，backup/isolate/inspect/restore已核验，runtime保持registeredNotRunning，registrationMutations=none。它明确报告`persistentAudit=notIntegrated`和productionGate=disabled；没有把未执行的bootout/权限操作记为成功，也不代表重启恢复绑定或完整故障矩阵通过。
