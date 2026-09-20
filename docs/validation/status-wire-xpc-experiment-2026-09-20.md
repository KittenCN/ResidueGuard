# Status-only 有界 wire XPC 实验

## 实施设计与边界

新增独立 Swift client/server 与最小 ObjC protocol bridge，不改变旧 IPC ping targets、构建脚本或五场景。新接口只传 NSData 帧和 NSData 回复；正式 HelperRequest DTO 不扩展。只有 status 可返回固定实验状态，prepare、executeOnce、executionStatus、prepareRecovery 全部拒绝。没有 HelperPolicy、VerifiedCaller、计划注册、token 签发、文件/服务操作或授权能力。

连接激活前设置当前构建双向 cdhash requirement；两端使用实际连接 EUID 与 audit session ID 对照本进程当前值，未知/不匹配拒绝。session 使用公开 getaudit_addr，而非 POSIX getsid。外部 manifest 仅为受控实验 harness 数据，不是生产信任根；篡改它能改变实验 pins，不得迁入产品认证。

帧上限 16 KiB、回复上限 2 KiB；每连接最多 8 条、服务最多 4 连接、同步有界解析，客户端顺序调用。NSXPC 接口仅允许 NSData。应用大小检查发生在 XPC 收包之后，不能声称约束了系统反序列化之前的全部资源。连接失效不自动重连或重试；客户端/服务端有固定退出期限。

固定场景覆盖正向 status、四种非status拒绝、超限/重复字段/版本/截断拒绝、消息数量上限、主动失效后请求、双向错误pin、UID/session谓词不匹配，以及同一签名二进制更正外部pin后的正向对照。UID/session不匹配场景只改变实验的期望谓词，不创建另一个系统用户或登录会话，不能称真实跨用户验收。

新构建器只构建、组装、ad-hoc签封与strict验证，不运行宿主GUI/XPC。客体runner零参数，必须VirtualMac、非root、27.0.0/26A428，固定自包含lab布局及固定场景；没有IPC路径/命令输入。VM运行由主任务独立执行。原实验五场景保持兼容，本任务不重复运行它们。

当前仅设计开始；后续实际构建/测试结果在文末追加。未安装helper，未创建证书/keychain，未改变生产gate。

## 代码交付与审查修正

新targets为 StatusWireClient、StatusWireServer、StatusWireBridge、StatusExperimentModel 与其测试。只有包清单增加这些targets/ResidueSecurity依赖并明确Swift 6；旧IPCClient/IPCServer/IPCWire与旧build_lab/run_lab/run_vm_lab/launch_case完全未改。

审查发现并修正：公开SDK定义AU_DEFAUDITSID=0，故本实验同时拒绝0和负audit session，不能把未知session当作已匹配。消息预算前8次允许解析，第9次最多发送一次messageLimit并进入terminal，随后invalidate；排队的后续消息不再进policy。NSXPC发送barrier不保证回复交付，所以VM断言第9次允许messageLimit或transportRejected，但前8次必须全部statusOnly，timeout不算通过。client遇到timeout/transportRejected/peerRejected立即停止该序列。

服务最多接受4个生命周期连接，第5个拒绝；这个实验上限比只限制同时连接更严格。主动失效场景必须先得到statusOnly，再同一连接得到transportRejected，不自动重连。两端实际UID/session核验不是VerifiedCaller认证：外部cdhash pin manifest仍可被harness替换，报告始终manifestTrustedForProduction=false。UID/session mismatch是改变实验期望谓词的正反对照，不是另建账户/会话的系统验证。

客户端10秒、服务端12秒自限；VM runner为启动器另设10秒界限，成功启动后结果及两个精确自有executable路径退出检查20秒，避免与server watchdog同为12秒的临界竞态。父脚本仅在启动器超时终止自身open PID，不按模糊名称杀进程。

## 本轮实际验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueIPCExperiment`：7项Swift Testing全部通过；仅模型/codec/预算/谓词测试，无真实连接。日志 `.local-evidence/status-wire-tests.log`。
- `python3 Packages/ResidueIPCExperiment/script/build_status_lab.py`：成功。构建16套完整.app+nested.xpc，逐一先签内部再签外层、deep/strict验证；ditto到新目录后重新strict验证。构建器没有运行任何client/server/app。日志 `.local-evidence/status-wire-seal.log`。
- 两个新shell通过bash -n，Python builder通过AST解析；git diff --check通过。
- 新VM产物：`Packages/ResidueIPCExperiment/.build/status-wire-lab-3CECB3A7-C8CF-432F-818C-EF957B50F348`，随附零参数 `run_status_vm_lab.sh`，执行需复制整个目录并保留600 manifest权限。
- 宿主真实XPC：notRun（与另一个GUI验证任务避免并行干扰）；VM真实XPC：notRun（由主任务执行）；旧五场景本轮notRun，保留原已记录证据，不能算本轮回归通过。

环境：macOS27.0/26A428 arm64、Xcode27.0/27A266a。独立代码审查确认修复session0和terminal预算后，未发现阻止受控VM实验的新问题；这不是生产认证、helper或安全认证结论。无证书/keychain/helper创建，无生产gate变更。
