# 隔离 macOS 能力验证与发布准备

本文件是可执行前的准备清单与验收契约，不是已经运行的清理脚本。适用于 P0 的平台实验以及 P3–P6 的安全放行。任何代码测试通过都不会自动开放 mutation。

## 早期只读盘点（2026-09-20，已由后续 VM 配置更新）

本轮实际执行了：

- 仅检查 `/Applications`、当前用户 `Applications` 顶层名称中的 UTM、Parallels、VMware、VirtualBuddy、VirtualBox；未发现匹配。
- 检查常见安装路径和 `PATH` 中 `tart`、`limactl`、`qemu-system-aarch64`、`prlctl`、`VBoxManage`、`utmctl`、`vfkit`；未发现可用命令。
- `security find-identity -v -p codesigning | tail -n 1` 仅取最终计数：`0 valid identities found`。没有输出身份名称/指纹、读取私钥或导出证书。

检查范围有限，不搜索磁盘镜像、VM 私有配置、下载目录或其他用户数据。因此结论是“本次范围未发现现成隔离工具/可用签名身份”，不能写成“主机没有任何 VM/证书”。Apple Virtualization framework 的系统存在也不等于已有可回滚测试 VM。

没有安装开发/虚拟化工具，没有启动或创建 VM，没有创建测试账户，没有调用 sudo，没有卸载/重置/注册服务，没有读取 TCC/BTM 数据库，没有实际签名/公证提交。以上窄范围探测不是 ISO-01–08 能力实验通过。

## 测试环境入场条件

先记录以下条件，再由后续明确任务启动实验：

1. macOS VM 或明确指定的独立测试主机/账户；共享配置、root helper、系统 daemon、全机作用域场景必须在可回滚 VM/独立测试主机，单独用户账户不能隔离宿主全机副作用。
2. 经核验可恢复的初始快照/回滚点、测试范围、存储上限、网络策略和销毁方式；先确认实验数据不含日常工作文件。
3. 精确 OS version/build、架构、Xcode/SDK、文件系统大小写模式、挂载卷、账户角色；一个 profile 的结果不推广到其他 build。
4. 本项目拥有的测试 app/Agent/helper，使用独立名称和标识，例如 `example.residueguard.fixture.*`。测试只操作该清单中的对象，不复用实际第三方软件。
5. 满足测试类型的签名身份。ad-hoc 可以帮助本地编译，但不作为 Developer ID 或稳定 helper 信任证据。测试身份与发布身份分 profile；密钥和证书不进仓库。
6. 清理备份目录、journal 与权限边界在测试环境内；root 备份 root-owned，执行侧生成路径，禁止 GUI 自报任意目的地。
7. 每项先确认 capability/实际影响/必要授权、不可变摘要和有效期；系统认证不抵扣产品确认；未知/保护/未界定的范围不执行。

工具和系统安装、VM 创建、身份签发/导入、证书或公证凭据准备不属于当前自动动作。需要时由后续明确任务确定具体环境；不为追求阶段完成在日常 Mac 替代验证。

## 实验运行顺序

先执行 [provider dossier](validation/provider-dossier.md) 的 ISO-01/02 只读及存在性测试，保存脱敏原始记录与 parser 对照。随后在独立测试范围依次进行：

| 组 | 动作范围 | 必需观测 | 不能推出的结论 |
|---|---|---|---|
| P3 用户配置 | 本项目单个用户 Agent：备份、精确卸载、隔离、恢复 | 文件身份/hash/metadata、精确 domain/Label/runtime、备份校验、journal、BTM 历史分项状态 | 文件移走不等于 BTM 行删除；恢复不等于服务重启 |
| P3 故障注入 | 备份/日志不可写、磁盘满、同名替换、服务卸载失败、逐步进程终止、恢复冲突 | 最后已确认步骤、尚未执行步骤、拒绝原因、只读恢复建议 | 失败不能报告全部回滚；重启不能自动继续删除 |
| P4 helper | 自身注册/用户批准/签名握手/升级/移除 | 真实连接身份、账户、要求表达式、token 一次性和审计结果 | 同 Team、PID 或路径不能独立证明授权 |
| P4 攻击 | S01–S11/S14：伪客户端、跨用户、重放、篡改、目录/链接/备份替换 | 请求被拒且无目标副作用，故障发生在哪个 gate | mock 拒绝不等于真实 XPC 拒绝 |
| P4 多会话 | 自有共享 Agent、system daemon | 所有受影响活跃会话；不可核验即阻断 | 共享源不能假称当前用户范围 |
| P5 精确权限 | 本项目已安装/真卸载 bundle、路径 client、caller-target、用户/系统 scope | service 白名单、确切影响粒度、返回码、后置可见状态与 UI 历史 | reset exit 0 不等于列表行消失；旧授权不可备份恢复 |
| P6 发布生命周期 | 干净环境首次启动、拒绝权限、安装/升级/撤销自身 helper、卸载 | Developer ID/Hardened Runtime、公证/staple、离线启动、拒绝后可用性与残留 | 本地 Debug 或一个 OS 通过不等于已发布兼容 |

每次改变版本/签名/目标身份/profile 都重新生成计划与确认。精确 reset 失败不执行更宽范围兜底；macOS 27+ 不进行 TCC 直读实验；全局 BTM/TCC reset 不进入产品或本测试计划。不得关闭 SIP、修改私有数据库、挂载未授权卷或执行被扫描程序。

## 证据与结果结构

每个实验保存：case ID、OS/build、源码 revision、provider/parser/policy 版本、测试身份类别（不含证书秘密）、限定对象清单、原始状态/摘要、命令和固定参数、时间/退出码/错误、前置确认、备份/journal 校验、动作分项结果、后置复查和回滚结果。

状态只能是 `passed / failed / skipped / notRun`。执行了命令但不能验证后置效果属于动作层 `unverified`，不能将测试判为通过；未具备隔离环境为 `notRun`，不是 `skipped=passed`。预期失败测试只有在已运行且确实拒绝并验证零副作用后才可 passed。

原始日志、签名标识、路径和许可记录仅保存在受限本地证据目录，不提交 git。仓库提交脱敏摘要与最小合成/授权脱敏 fixture，避免完整软件清单和隐私授权记录。版本 profile 只根据实际通过证据增加能力，不能手工把所有 mutation 标成 true。

## 当前放行结论

ISO-01–08 及 P3/P4/P5 的实际系统修改、签名信任和 P6 分发实验仍 `notRun`。可以继续开发/测试纯事务策略、恢复规划、协议校验、只读采集与 UI；这些工作有独立价值，但不构成真实清理或正式发布验收。

## 后续 VM 更新

用户已安装并打开 VirtualBuddy；现已建立正常关机后的回滚副本并设置项目专用交换目录。早期未发现 VM 的结论不再是当前阻塞。客体重启等待本地登录；真实集成测试仍未执行，备份尚未完成启动恢复演练。详见 [VM 接续报告](validation/vm-continuation-2026-09-20.md) 和 [实验夹具](../Tests/Integration/VM/README.md)。
