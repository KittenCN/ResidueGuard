# ResidueQuarantine：单文件同卷隔离/恢复原型

Swift 6 / macOS 14+，依赖 `ResidueBackup`。没有公开构造器、生产路径工厂、GUI接线或VM入口。只有包测试可以注入已经打开的自有临时源/隔离目录fd和可信Backup对象；没有任意路径、shell或服务接口。production gate 保持关闭。

`isolate(receipt:planID:)` 先核验计划UUID、受信receipt和备份manifest/内容，检查源当前身份指纹、大小/hash/全部有界xattr；源目录只允许当前uid所有且无组/其他写，隔离目录必须0700，目录/文件有ACL、危险flags、非普通文件或hardlink均拒绝。源与目标目录 device 不同直接拒绝。只执行目录fd锚定的 `renameatx_np(..., RENAME_EXCL)`；不回退到覆盖rename或copy-delete。隔离文件名由备份UUID固定生成，不由外部路径提供。

移动后检查原名称缺失，以及隔离名称的device/inode/uid/gid/mode/size/mtime/hash/xattr与备份绑定的源一致，允许rename自然改变ctime；之后重新验证目录和备份，fsync两个目录。源隔离前仍要求ctime匹配备份。`restore`反向独占rename，先验证可信备份和隔离物体；原路径任何对象（包括dangling symlink）都阻断。恢复保持同一inode，不启动服务，不恢复权限授权。

结果明确区分：

- `notMoved`：本次rename未成功；返回原因，不能推断其他进程未改状态。
- `movedUnverified`：rename成功但后置核验或持久化失败；必须停止并只读检查，不能假称未动或自动补偿。
- `quarantinedVerified` / `restoredVerified`：本次指定文件移动及后置校验通过；不代表服务、BTM、TCC或完整事务完成。

**重要竞争边界**：公开rename接口不能原子地绑定“仅当源inode仍等于计划才移动”。恶意进程可在最后读取与rename之间替换源。本原型能在移动后发现该异常并报告`movedUnverified`，但可能已经移动替换物。测试刻意证明这一限制；不会删除、覆盖或自动搬回异常对象。不得把本原型描述为不可竞争，也不能直接上线产品清理。对同UID完全控制攻击者、目录命名空间变动、突然掉电、全部故障组合均不作保证。需要生产设计审查与VM验证后决定是否能形成满足安全门的策略。

调用方将来还须验证用户确认、影响集合、计划时效/签名、源所属固定根、服务卸载/确切未注册、一次性token及持久journal。此模块只比对计划UUID，**不声称已校验有效期或服务前置条件**。恢复前新版本/归属审查也不属于此模块。没有后台重试、自动删除或启动逻辑；内部故障注入闭包仅供测试。

验证命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueQuarantine
```

全部写入/ACL试验发生在测试新建的随机临时目录。20项真实文件API测试通过。真实跨卷测试、客体VM实验、进程崩溃/断电测试未执行。API依据为当前系统 `renameatx_np(2)` 手册：`RENAME_EXCL` 返回EEXIST保护已有目标；平台/卷不支持时直接失败。

## 只读恢复检查

`inspectRecovery(receipt:planID:)` 使用同一受信receipt绑定的源名和隔离名，核验备份、私有存储和两处对象，不调用隔离/恢复方法。结果分别报告源和隔离对象的`absent`、`matchesReceipt`、`conflict`或`unverified`。原源仍在只表示`sourcePresentNoMoveRequired`，不能推断曾执行恢复；源缺失而隔离物匹配只产生`restoreCandidateRequiresNewPlan`，不执行恢复。两处缺失、冲突、dangling symlink、ACL/权限问题、篡改备份均显式分类。

结果的`permitsMutation`、`runtimeInspected`永远false；对象匹配允许rename导致的ctime变化，但仍核验其他身份、mtime、内容和xattr。这是顺序读取的时间点观察，不是跨对象原子快照，也不验证计划有效期/新版本安装/服务运行状态。需要持久受信receipt重建、运行状态及新恢复计划才能接启动恢复界面，不能加载磁盘manifest便直接授权。

2026-09-20新增10项只读恢复测试，合计30项通过。未新增VM可执行入口：现有Backup VM probe只返回脱敏摘要，无法跨包安全传递受信Backup对象和receipt。下一步应设计独立受限lab context或测试目标桥接，不临时开放任意路径/fd生产构造器。实际文件移动的VM端到端实验仍未由本包证明。
