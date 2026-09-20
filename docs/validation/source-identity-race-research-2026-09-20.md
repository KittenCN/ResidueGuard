# 源身份复核到文件移动的竞争：公开接口研究

日期：2026-09-20。研究对象为当前 `QuarantineStore.move` 的源指纹检查到
`renameatx_np` 的间隔。本次仅阅读仓库代码、本机man/SDK和Apple官方资料；没有执行
删除、隔离、权限调整、文件系统冻结或系统服务操作，也没有修改执行代码。

## 结论与证据强度

在本次检查的macOS公开文件接口中，没有找到“当前目录项仍对应指定源fd/inode/hash
才原子rename或unlink”的受支持契约。因此，现有实现不能通过任意第三方配置文件的
生产清理安全门。此结论只覆盖已核查接口，不声称证明所有系统版本、所有潜在接口或
未来API都不可能提供这种能力。Apple开源XNU用于解释机制，不等同已证实其main分支
就是当前26A428运行内核的逐字源码；本机SDK/man是本轮接口核查的另一条独立证据。

当前代码已做到源/目的目录fd锚定、备份核验、完整源指纹检查、目标不存在检查、
`RENAME_EXCL`、移后身份/位置检查及目录fsync。但rename的源参数仍是目录fd和名称。
在最后一次检查后，安装器可以把同名目录项A换成B；随后rename移动B，移后核验发现
不匹配并返回movedUnverified。这是正确的事后止损，却不能使此前移动B变成用户对A的
有效授权，也不能证明B已有对应内容备份。

## 本机公开API证据

读取了以下手册和项目固定Xcode SDK头文件，没有调用其中的变更接口：

```text
man 2 renameatx_np
man 2 unlink
man 2 clonefile
man 2 flock
man 2 fcntl
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sys/stdio.h
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sys/fcntl.h
```

| 接口或标志 | 已核实的作用 | 不成立的推论 |
| --- | --- | --- |
| renameat/renameatx_np | 用起始目录fd和名称解析源、目标 | 起始目录fd不是预期源文件fd；签名没有预期inode/hash参数 |
| RENAME_EXCL | 目标已存在时报错，避免覆盖 | 不限制当前源名称指向哪个对象 |
| RENAME_SWAP | 原子交换解析到的两个名称 | 原子交换不等于检查过的对象仍在该名称上 |
| RENAME_NOFOLLOW_ANY/RESOLVE_BENEATH | 拒绝符号链接或越过起始目录层级的解析 | 不比较过去观察的源身份 |
| unlinkat | 相对目录fd移除指定名称 | 仍重新解析名称，不是按打开的源文件fd移除 |
| AT_NODELETEBUSY | 当前解析对象存在打开fd时报错 | 打开A可能阻止删除A，但A被B替换后，未打开的B仍可能满足该条件 |
| AT_UNIQUE | 当前解析对象多硬链接时报错 | 一个新B也可只有一个链接，并不代表是原A |
| fclonefileat | 从源文件fd创建克隆，目的必须不存在 | 能用于对象绑定复制研究，但不会移除源目录项；不是隔离替代 |
| flock/F_SETLK/OFD locks | 协作式文件/记录锁；OFD改变锁的持有生命周期 | 未参加协议的进程仍可访问，不能约束所有目录项替换 |

这些标志不能组合成所需的比较交换：只要最后一步按名称选择源，而预期身份检查是
之前的独立调用，就存在检查与最后名称解析之间发生替换的合法调度。将最后一次stat
移得更近、重复多次核验或监听FSEvents只能缩短/发现窗口，不能使两个系统调用原子化。

## 官方资料交叉核查

- [Apple XNU vfs_syscalls.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_syscalls.c)：`renameatx_np` 接收fromfd/from/tofd/to/flags，再进入名称解析和rename实现；没有从用户态传入预期源inode或源文件fd的条件参数。内核内部的vnode/namei锁保障该次文件系统操作，不把此前用户态核验纳入同一事务。
- [Apple文件协调指南](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileCoordinators/FileCoordinators.html)和[NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)：文件presenter需要注册并参加协调；本研究没有找到它强制约束任意第三方POSIX写入者的承诺。可以协调我们控制的访问者，不能据此宣称所有安装器会暂停。
- [Apple XNU kern_descrip.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_descrip.c)：`F_UNLINKFROM` 明确是SPI，要求目录vnode，仍调用相对该目录的路径unlink；既不属于本项目可用公开方案，也不是按源文件fd比较删除。
- [Apple XNU vfs_subr.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_subr.c)：`vnode_setlease` 通过`allow_setlease`检查专用entitlement，lease冲突还存在超时打破机制。SDK出现`F_SETLEASE`宏不等于普通App拥有可用、不可打破的独占权。没有申请或绕过这种权限，也不借开发内核开关改变平台保护。
- 本机SDK存在`RENAME_SECLUDE`宏，但当前读取的rename手册没有给出所需的预期源身份条件契约；不能由宏名或未文档化行为推导安全承诺。

以上均为接口/源码静态核查，不是新的竞争实验结果。已有仓库竞争负例和VM实验应按各自
验证报告引用，不由本研究虚构测试次数或通过结论。

## 正常意外并发与恶意同UID是不同问题

正常安装器/自动更新器无需恶意，也可能采用写临时文件后原子替换plist的流程。应用本体
已退出、服务已bootout、扫描显示疑似残留，均不能证明独立更新进程不会这样做。用户对A
的两次确认也不授权后来出现的B。这种普通并发属于现有产品应处理的风险，不能仅用
“不防御完全控制同UID的攻击者”将它排除。

恶意同UID进程是更强的威胁：0700目录不能隔离同一UID，它可以忽略advisory lock、替换
名称或改写用户拥有的内容。项目可以明确不承诺抵御完全控制同UID的进程，但这种范围
声明不能消除上段的正常更新竞争，也不能把扫描所得的“似乎没有写入者”当成证明。

helper/root不会自动增加expected-inode原子rename语义。临时chmod/chown/ACL夺取
第三方目录控制、设置锁定flags、暂停其他软件或冻结整个卷都会扩大实际影响，可能
中断正常安装/写入，而且此前已打开的写入fd和特权写入者还需单独分析。这些操作既没有
被本次授权，也不能作为现有安全门的隐藏补丁。不得弱化SIP、使用私有绕过或自动修复
系统权限以使实验成功。

## 可行生产范围与产品降级

1. **受控自有对象**：只接受本产品自身管理的固定对象；全部合法写入者采用同一串行
   协议，覆盖从最终复核到移动和结果记录的临界区。私有根、固定名称/签名身份、生命周期
   管理和对更新器的协议约束共同构成可检验假设。0700和锁各自都不足以证明所有写入者
   已受控。固定VM自有夹具可以在此范围继续测试，但公开LaunchAgents目录中的自有Label
   仍需显式记录“写入者受控”的实验假设，不能推广成第三方安全保证。
2. **第三方来源只读**：保留身份/coverage证据、变化提示、备份/历史只读核查及明确手动
   处理指导；不把证据不足对象接入隔离按钮。可研究第三方自己提供的受支持卸载/管理
   API，但要有窄契约和真实验证；SMAppService不能被包装成通用第三方卸载器。
3. **先发现再行动**：身份或范围变化使旧计划失效；新观察需要新计划和确认。移动后
   不确定时停止依赖操作、保留实际效果/证据，绝不自动删除异常对象或搬回覆盖源。此类
   止损仍不等于满足移动前身份不变要求。
4. **若修改产品风险契约**：必须显式提出设计修订和可检验恢复承诺，而不能只增加确认
   次数后把未知换入对象纳入原计划。当前“仅作用于已确认身份、改变则失效”的不变量
   没有被本研究修改。

因此可继续推进自有受控场景、持久日志/中断矩阵和第三方只读产品；不能宣布通用第三方
自动清理的源身份竞争已从根本解决。是否未来存在新公开原语或有完整写入者协议的具体
来源，应逐来源重新研究与验收，而不是扩大现有fixture profile。
