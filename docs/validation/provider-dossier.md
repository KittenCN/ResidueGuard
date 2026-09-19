# P0 来源能力档案与隔离验证计划

日期 2026-09-20；宿主 macOS 27.0 / 26A428 / arm64。证据等级分为“文档已读”“SDK 声明已读”“合成策略测试”“OS 集成实测”；前三者均不替代最后一项。本次没有真实用户源记录或脱敏真实采集 fixture；`fixtures` 均为合成数据，不冒充系统样本。所有运行时 provider/parser profile 未验证；所有 mutation 关闭。

## 只读资料核验

| 来源 | 本次获得的证据 | 能说明什么 / 不能说明什么 |
|---|---|---|
| 用户/共享/system LaunchAgents、LaunchDaemons | 本机 `launchd.plist(5)` | Label 是服务身份；Program 指定可执行路径；没有 Program 时 ProgramArguments 首元素按机制解释；BundleProgram 仅 SMAppService 安装的 plist 可用。不曾枚举本机目录、验证访问权限或取得配置样本。系统自带源永久受保护。 |
| launchd runtime | 本机 `launchctl(1)` 的 domains、print、bootstrap/bootout 章节 | user 和 gui 域不等同；print 输出不属于稳定 API。后续必须记录 OS build/parser version 并保留未知行。没有运行 print、bootout、bootstrap、enable 或 disable。 |
| BTM / 登录项 | [Apple Platform Deployment](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web) | dumpbtm 是诊断读取，resetbtm 是重置；本文不推导通用逐条删除。未运行 dumpbtm，未获取用户软件清单、输出大小或多用户记录，相关覆盖与权限仍未知。resetbtm 不进入产品。 |
| SMAppService | SDK `ServiceManagement.framework/Headers/SMAppService.h` | 管理调用 app bundle 内自身 helper，loginItem identifier 必须对应自身 bundle 内 LoginItems。register 可能启动服务，unregister 可能终止服务，均非只读探测。未注册、查询第三方或安装任何服务。 |
| TCC reset | 本机 `tccutil(1)` | 文档有 command/service/可选 bundle_id 参数；未提供全量第三方枚举接口。未证实 token、卸载 bundle 解析、路径型 client、自动化 caller-target 粒度及后置 UI 效果；不执行 reset。 |
| macOS 27 TCC | [官方 release notes JSON](https://developer.apple.com/tutorials/data/documentation/macos-release-notes/macos-27-release-notes.json)，90775556 | 本次读取到禁止直接访问本地 TCC 数据库的条目；据此基线禁用。未访问数据库、未做绕过或复制实验。完整第三方权限清单显示 unsupported，提供手动引导。 |
| XPC peer 身份 | SDK `Foundation.framework/Headers/NSXPCConnection.h` 和 `usr/include/xpc/connection.h` | 公开声明 NSXPCConnection.setCodeSigningRequirement、NSXPCListener.setConnectionCodeSigningRequirement，macOS 13+。listener 接口仅适用于 anonymous/Mach service listener；签名规则应在连接激活前设定。不能据此声称签名双向校验和权限模型已验收。 |
| 本地网络/定位/通知、MDM、扩展 | 本轮未做各自 API/OS 实验 | 不猜 TCC token；保持 guidedOnly/受保护，不标成扫描成功空列表。 |

SDK 根为 `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`。Apple 文档正文普通 HTML 在工具中仅显示 JavaScript 提示；release notes 通过官方 JSON 读取成功，SMAppService 结论以本机 SDK header 为证。文档摘要不是系统集成结果。

## 后续来源字段与覆盖契约

每条记录保存 provider/native identity/scope、source artifact、观察时间与 generation、原始未知字段和 parse warnings。Launchd 记录至少保留 Label、Program、ProgramArguments、BundleProgram、目标与归属证据；BTM 若未来可取，则保留原生 ID/类型/状态/父子关系，不臆造数值语义。权限记录必须区分 service、client_type、caller/target 及 scope。

每个采集结果报告 declared roots/user scopes、parsed/unparsed、拒绝/跳过区域、错误和 coverage 状态。未建立稳定身份、未知 schema、超量截断、多用户无法过滤均不能变成成功空列表。保留未知原始行时必须限制大小、脱敏、仅本地存储；不能提交个人路径与软件完整清单。

当前阶段没有这些真实字段样本，因而解析损失、真实输出上限、有效权限与实际覆盖均标 `notRun`。P1 演示值只能验证策略和 UI。

## 隔离能力实验计划（全部 notRun）

共同准入条件：另行授权后，在可回滚 macOS VM/专用测试账号中使用本项目签名测试 app；保存快照 ID、OS build、签名身份、安装清单、精确命令参数、退出码、观察时间及前后证据。每个 OS/build 单独 profile，未知 build 不继承写能力。普通用户和管理员测试分开，不采集其他用户私人数据。

| ID | 有界实验 | 后置验证 / 失败标准 | 当前 |
|---|---|---|---|
| ISO-01 | 创建本项目单个用户 LaunchAgent，只读解析 + 精确 runtime 关联 | Label/domain/文件/执行身份一致；重复 Label、截断、新 schema 降级 | notRun |
| ISO-02 | 测试 app 移动、Trash、真正移除、重装、同 ID 副本、离线卷与合法 CLI | 已安装/未知/离线/Trash/共享 owner 不标高可信残留；不主动挂载 | notRun |
| ISO-03 | 本项目 BTM/登录项登记样本及源配置隔离 | 分开记录文件、运行状态、登记历史；历史未消失不得声称全部删除 | notRun |
| ISO-04 | 单个测试 Agent 备份、精确 service bootout、配置隔离、恢复 | 指纹/备份/journal 先行；失败停止；恢复配置不自动启动；禁用无 service 的域级 bootout | notRun |
| ISO-05 | 测试 bundle 已安装/真正卸载后的逐 app、逐 service reset | 记录 bundle 不解析和授权失败，绝不扩大 reset；不可恢复旧授权 | notRun |
| ISO-06 | 路径型 client、自动化 caller-target 与 scope 粒度 | 实际影响扩大即阻断原计划；未知影响禁止；UI 历史变化独立记录 | notRun |
| ISO-07 | 自身 helper 安装/批准/升级/注销 + XPC 恶意客户端 | 签名/账户/过期计划/重放/替换路径/任意命令拒绝；完整生命周期验收前不开 mutation | notRun |
| ISO-08 | 共享 Agent 多用户作用域和保护项 | 全部实际影响展开；活跃安装方两次确认；未知/受保护直接阻断 | notRun |

不规划 macOS 27 TCC 直读实验、不规划全局 BTM/TCC 重置、不把用户日常软件作为 fixture。没有隔离环境是未执行原因，不是通过证据。未来验收必须同时有机制支持、身份校验、实际影响、备份、产品确认、OS 认证（适用时）和后置验证；仅 exit 0 不足以放行能力。

## P0 范围结论

环境和文档级能力边界已核验；P0-02 真实采样、P0-03/04 OS 实验、P0-05 签名/helper 集成仍 notRun。允许以明确演示数据、禁用执行器的方式进入 P1；不宣称 P0 全部 OS 能力验证完成。
