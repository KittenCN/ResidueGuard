# 用户级真实清理接入前安全门审查

审查日期：2026-09-20。范围为当前 Core、Platform、Backup、Quarantine、Persistence、Transactions 的源码和已提交测试；本审查没有修改执行能力、生成 helper 或操作系统服务。目标是本地用户级功能，不依赖 App Store、Developer ID 或公证。没有签名分发身份不是下面开发工作的阻塞理由。

## 结论

**不能把当前隔离原型直接接到真实第三方 LaunchAgents 清理按钮。** 当前 fd 锚定、备份、RENAME_EXCL 和移后校验解决了许多问题，但最后核验到rename之间仍能移动换入的新对象。普通软件更新也能触发，不只发生在威胁模型排除的“同UID完全控制恶意进程”场景。

项目仍有大量可自动进行的编码和VM测试，不需要用户先购买证书、打开SIP/TCC保护或批准宿主清理。合理的下一闭环是**固定自有VM夹具的受限事务driver + 持久化恢复证据 + 故障矩阵**，继续保持第三方真实来源只读。

## 已有组件与尚未成立的推论

- Core 已有影响集合归并、独立确认事件、120秒计划期限、取消/重放策略及合成事务协调；`TransactionGate`只有closed/syntheticTests，`VerifiedTransactionPlan`只接受synthetic profile。不能由dry-run直接生成真实执行凭据。
- Platform 对配置目录和应用目录作有界只读观察；扫描明确保留部分覆盖/未知/疑似残留。顶层应用索引不是完整归属证明，也没有已验证的全量共享依赖图。
- Runtime collector 只有指定build/profile下的`running`和`registeredNotRunning`，错误仍为unknown。**registeredNotRunning不等于未注册**；当前没有可信`absent`类型可让driver跳过卸载。
- Backup 已有读取/指纹/manifest/验证；固定VM入口可验证自有ISO01。Quarantine仍只有内部测试构造入口。二者没有生产固定根工厂或真实App授权桥接。
- Transactions 把合成协调器接到SQLite日志，但`TransactionOperations`仍是注入接口，没有真实OS typed adapter。Core的`VerifiedBackup(verified: Bool)`不是Backup包的完整receipt，也不能充当生产备份凭据。
- 当前journal保存planID/digest/nonce、operationID和三态结果，尚不保存恢复所需的受信backupID、完整源身份、隔离对象身份、实际effects等绑定。重启后不能仅凭目前几列安全重建一个恢复计划。
- GUI项目设置仍为App Sandbox + `ENABLE_USER_SELECTED_FILES=readonly`。真实用户级写入需要单独设计的授权来源、明确产品确认与当前安全范围；不能因为CLI夹具能写就推断GUI可写。

## 最后核验到rename的竞争审查

普通更新序列即可复现风险：用户批准旧inode A；更新器用临时文件B原子替换同名plist；清理器执行`renameatx_np`，移动的是B；移后读取发现B与A不符，报告`movedUnverified`。代码没有删除B或自动搬回，属于正确止损，但B可能属于刚安装的软件、未被批准，也没有对应内容备份。原来的确认和备份都不能授权这个对象。

这满足docs/04中“身份异常停止、不删除异常对象”的部分要求，却没有完整满足“计划身份改变则确认失效”“所有源变更必须对应新鲜身份/已验证备份”“不知道的实际影响被阻断”。因此当前实测并非生产安全门通过。不能用“同UID攻击不承诺防御”把普通安装/更新的非恶意并发排除。

本机 `renameatx_np(2)` 以及SDK `usr/include/sys/stdio.h` 的公开签名是目录fd、两个名称和flags，没有传入预期源inode/hash的参数。RENAME_EXCL防止目标覆盖；NOFOLLOW/BENEATH约束路径解析，不能绑定过去读取的源对象。Apple公开XNU实现同样将这些名称/flags转入rename路径；内核内部vnode锁不等于用户态核验与调用之间的compare-and-rename。[Apple XNU源码](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_syscalls.c)

**本次检查到的公开接口没有提供所需的“源身份等于预期才rename”契约**；这不是声称穷尽证明所有未来系统API都不存在。SDK虽定义RENAME_SECLUDE，本机手册没有给出其解决该问题的承诺，不把宏存在当成可用安全方案。不使用私有fsctl/内核API猜测绕过。

`NSFileCoordinator`向注册的file presenters协调操作，是可以研究的合作式减少冲突措施；Apple文档要求相关对象注册/参与协调。不能据此推断任意第三方安装器或直接POSIX写入者会被强制阻止。它可以改善自有写入者的同步，不能单独通过这里的第三方源安全门。[Apple文件协调指南](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileCoordinators/FileCoordinators.html)、[NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)

本机 `flock(2)` 明确是advisory lock；文件锁不约束不参与协议的更新器，也不能把“锁住打开的A”变成“同名目录项永远还是A”。增加重复stat、缩短间隔、延迟等待、FSEvents监听或让用户退出主App只能降低发生概率，不能形成原子身份承诺。也不能改第三方目录权限/owner、锁整个LaunchAgents目录、停止不相关更新服务来悄悄扩大影响。

## 精确剩余门槛与可自动下一步

| 门槛 | 当前缺口 | 可自动执行的下一实现/验收 |
| --- | --- | --- |
| 真实计划与影响 | synthetic plan和只读扫描不能证明第三方归属/共享依赖 | 定义独立`OwnedFixturePlan`及不可伪装成production的VM profile；将固定Label、uid、source/程序身份、OS build、backupID、有效期全部绑定摘要。未知/共享/非自有对象拒绝 |
| 文件竞争策略 | 检查后源替换可能先被移动 | 保持第三方gate关闭；对全部写入者受控的私有夹具根实现单writer串行与只读状态重核，并保留源竞争负例。公开目录中的“服务未注册”本身不解决文件更新竞争 |
| Runtime前置 | 只有running/registeredNotRunning/unknown | 在固定VM自有fixture上验证精确卸载、失败及前后状态；单独定义带域、退出码、完整捕获和profile证据的fixture-only未注册观察。超时、权限错、截断、未知build不得变成absent |
| 具体事务连接 | Operations还是注入接口；Backup与Core receipt未桥接 | 新受限driver只接固定fixture；备份receipt与plan/step绑定，先持久prepare再动作；`movedUnverified`严格映射file.unverified并停止，不自动补偿 |
| 效果分类一致 | 审查时Core只看requiredEffect，driver额外拒绝registration.unverified | 统一共享成功判定并增加“最后一步file succeeded且registration unverified”的回归；completed与持久finalize必须一致，不能最后才揭露未验证 |
| 可恢复证据 | journal未持久存完整恢复绑定 | 新版本schema或独立受信记录存plan内容摘要、backupID/manifest摘要、源/隔离身份、步骤effects及阶段；未知schema仍拒绝，不通过重建DB丢失重放保护 |
| 真正重启恢复 | 当前只读unfinished视图不能验证系统对象 | 构建只读RecoveryInspection：重开journal/receipt并观察源、隔离、runtime，产出冲突/缺失/未知，绝不重做动作。新的恢复必须新计划/新确认 |
| App写入边界 | 现有用户选择授权只读 | 先在单独VM测试构建中验证明确选择自有目录的read-write授权和取消；保留主App生产gate关闭，拒绝任意路径/权限不足，不自动改系统隐私权限 |
| 故障与兼容矩阵 | 正常路径与临时夹具单测不能覆盖真实中断 | 固定VM做备份读回失败、prepare后中断、rename后journal前中断、恢复冲突、新inode/元数据变化、服务失败/权限拒绝/OS未知、跨卷拒绝；每个阶段记录实际文件与运行态，不能只统计返回码 |
| 性能与报告 | 系统I/O尚未全部纳入真实执行取消及UI状态 | 将文件工作放离MainActor，动作临界阶段取消后先观察/记录；GUI分别显示file/runtime/registration/permission，不把BTM历史待刷新称清空 |

后续：效果分类已修复并通过 Core 31 项与 Transactions 6 项回归，见 transaction-outcome-fix-2026-09-20.md；只读 RecoveryInspection 已实现并纳入 Quarantine 30 项测试，见 recovery-inspection-results-2026-09-20.md。受信持久恢复绑定与真实 VM driver 仍未完成。

## 当前可接受的收窄方案

1. **本地产品继续只读审计/报告/权限引导**。不需要Developer ID，仍可继续完善界面、扫描、覆盖和持久记录。
2. **在独立VM中的自有固定fixture范围完成真实交易实验**。不接受任意路径；无服务时只移动配置，已注册的自有服务先走经实测的精确卸载。实验profile不能赋给第三方扫描结果。私有测试根的受控writer约束及公开LaunchAgents中自有Label的夹具假设要分别记录，不能把一个推成另一个。
3. 对第三方配置，暂提供有证据的定位/手动处理指导；不因用户多点一次确认就忽略未知影响。若未来要改变第三方竞争风险契约，须先提出明确产品设计修订和可检验的恢复承诺，不静默降低现有不变量。

仅用户级、不安装helper的局部目标可以继续，不必为尚未实现的系统级共享清理先申请Developer ID。将来若实现helper，仍要独立满足调用者身份和窄操作接口，而不是因不分发就省略身份验证；本轮不开展helper安装。

## 哪些真的需要用户操作

**现在没有必须先让用户操作才能继续上述编码/固定VM实验的阻塞项。** VM已可用，用户已授权自有测试和必要软件启动。不要再要求提供已给过的登录信息，也不要把证书购买列为下一步。

以下事项仅在实际遇到时才需要具体用户参与：

- 系统弹出必须本人完成而自动化无法处理的登录/隐私/文件授权，需指出客体窗口、应用名和具体目录；不能提前泛化成“请开所有权限”。
- 需要增加尚未安装的其他macOS版本/VM磁盘/开发依赖时，先完成现有系统的工作，再请求具体资源；不擅自升级宿主系统。
- 若要把风险尚未解决的第三方清理纳入范围，需要审阅明确设计选择；普通“继续开发”不能替代这个安全设计，也不授权清理开发者的真实软件。
- 正式运行真实个人来源清理时，仍需产品内针对具体计划的独立确认；这与本次开发/VM测试授权不同。

无需用户操作的工作应继续自动完成：类型/状态机修复、受限driver、schema与只读恢复、临时夹具与自有VM故障测试、文档回写、适当构建与Git保存。不能在这些任务仍可推进时以“项目未发布/无Developer ID”为由停止。
