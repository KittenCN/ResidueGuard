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

## 首轮真实 VM 失败与窄诊断版

主任务实际执行v1时，首个accepted场景在20秒结果/退出检查后失败，未继续其他场景。本地导出的 `statusdiag-v1/*/accepted.out` 是合法实验JSON，但outcomes为 `["transportRejected"]`；accepted.err大小0。故不能把该失败记作通过，也不能仅凭脚本timeout文字断言是XPC超时。现有证据表明client入口/session/config/frame正常推进到连接请求，拒绝发生于连接或server，具体原因尚待阶段日志。

新增固定subsystem `example.residueguard.status-wire` 的统一日志：server入口、session查询失败/默认未知/可用、配置加载、listener进入、连接预算、UID拒绝、session拒绝、pin配置、激活/失效、消息入口与peer复核分别使用固定S_*阶段码。不打印路径、UID/session原值、pin或manifest内容。S_PIN_READY仅表示签名requirement成功配置，绝不表示真实peer已认证通过。client的transport error额外记固定C_TRANSPORT_REJECTED阶段、NSError domain和code；domain只保留长度不超过96的ASCII字母/数字/点/短横线/下划线，否则记unrecognizedDomain，不记录localizedDescription或userInfo。

runner失败现在分别报告outputAbsent、outputMismatch、ownedProcessPresent布尔；不放宽任何输出断言或身份检查。客体可在失败后只读运行以下固定subsystem查询并保存本地证据（本任务未执行）：

```sh
/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "example.residueguard.status-wire"'
```

诊断版本只重新构建/签封：7项模型测试通过，无warning/error；两个shell语法与diff check通过，完整16套app/XPC及复制件strict通过。新产物 `Packages/ResidueIPCExperiment/.build/status-wire-lab-E6306693-58B3-48F7-9C02-EB5596288D62`；日志 `.local-evidence/status-wire-diag-tests.log`、`.local-evidence/status-wire-diag-seal.log`。没有运行宿主app/XPC，也没有重跑VM；v1失败证据保留，诊断版实际VM仍notRun。

## v2 实际失败定位与 v3 非对称会话契约

主任务导出的 `.local-evidence/vm-transfer/status-wire-v2/stages.txt` 已证明 v2 的真实路径为 `S_ENTRY → S_SESSION_READY → S_CONFIG_LOADING → S_CONFIG_READY → S_LISTENER_STARTING → S_LISTENER_CALLED → S_PEER_SESSION_REJECTED`，客户端为 NSCocoaErrorDomain/4097。因此前节 v2 notRun 是当时构建状态，现由此次实际失败证据补充；没有任何真实 status 成功证据。

根因是错误地要求 XPC 服务自身会话与 GUI caller 会话相等。[Apple Creating XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html) 的 JoinExistingSession 说明，以及本机 `man 3 xpc_main`、`man 5 xpcservice.plist` 都明确：默认服务处于新 audit session，JoinExistingSession 默认 False。[NSXPCConnection.auditSessionIdentifier](https://developer.apple.com/documentation/foundation/nsxpcconnection/auditsessionidentifier) 是 connecting process 的会话；`getaudit_addr` 读取自身会话，两者角色不同。

v3 保留默认独立会话，不打开 JoinExistingSession，不为了通过测试扩大 keychain/UI 会话资源访问：

- 新零参数 StatusSessionReader 仅读本进程有效非零 ASID；VM runner 在既有门禁之后运行它，在新实验根生成600的固定 `status-session.plist`，将 expectedCallerSession 与该根 canonical UUID 绑定。值必须为规范正十进制字符串且不超过 Int32.max；缺失、额外字段、错误UUID、默认/负值均拒绝。外部manifest仍是实验数据，不是生产信任根。
- GUI client 在连接前独立读取自身ASID并精确匹配manifest；不同输出固定 C_CALLER_SESSION_REJECTED 并拒绝，无fallback。因此没有假定 Terminal、reader 和 open 启动的 GUI 必然同一会话。这个前提仍需实际VM验证。
- server 将连接实际callerASID与manifest expectedCallerSession比较，绑定到连接并逐消息复核；自身ASID仅检查可用性，不作为caller期望。sessionMismatch仅在server产生固定不等的期望，client仍走正常前置检查，测试server拒绝。
- client 在代码pin保护的首个合法回复后，记录该连接实际serverASID>0；后续仅接受相同值。每个连接各自记录，不要求connectionLimit的不同连接会话相同。timeout、transport错误、interruption、invalidation、错误peer均使观察绑定terminal，不允许重新学习。该观察不是跨会话授权，也不会创建VerifiedCaller或调用HelperPolicy。

实际验证：完整包Swift Testing **10项通过**（原7项+3项会话/manifest/终止状态回归）；首次新增断言遇到Swift Testing对mutating调用的宏展开编译限制，改用闭包表达式后重跑通过，不计首次失败为通过。日志 `.local-evidence/status-wire-session-tests.log`。构建/签封16套app/XPC与新增reader成功，原件及ditto复制件strict验证通过，日志 `.local-evidence/status-wire-session-seal.log`。新产物 `Packages/ResidueIPCExperiment/.build/status-wire-lab-081C75B7-0B50-4775-AF24-02889AA14043`。两个shell语法检查、Python编译检查、diff检查通过。未运行宿主app/XPC或reader，未执行VM；v3真实XPC仍notRun。原五场景和所有原始失败证据保持，生产gate不变。

## v3 真实 VM 验收

主任务随后在同一专用 VirtualMac、macOS27.0/26A428、普通客体账户运行v3：全部17场景通过，runner exit0，逐场景精确自有client/server进程均退出。包括status正向、4种非status拒绝、4种非法frame拒绝、8条消息后第9条限制、4连接后第5连接拒绝、主动失效后拒绝、错误client/server pin、UID/session期望不匹配，以及同一已拒绝二进制更正实验pin后成功。messageLimit本次实际第9条收到messageLimit；不是transportRejected替代分支。

证据：`.local-evidence/vm-transfer/status-wire-v3/status-wire-vm-results.txt` 与 `exit.txt`；主任务另行解析17条JSON并核对17条进程退出记录以及全部authorizesMutation=false、manifestTrustedForProduction=false。v1/v2失败保留，不能抹成从未失败。此结果验证本次GUI caller会话前提及连接内会话约束，不是跨真实用户/不同登录会话攻击验收；没有创建证书/keychain、安装helper或执行系统清理。宿主真实XPC与原五场景本轮未重跑。

固定subsystem阶段日志另确认v3命中S_CONNECTION_LIMIT、S_PEER_UID_REJECTED、S_PEER_SESSION_REJECTED，对应预算与UID/session负例确实到达服务端拒绝阶段；原始日志仅保留本地。统一测试入口新增 `./script/test.sh ipc-model`，实际10项通过（0.003秒），不运行真实XPC，日志 `.local-evidence/status-wire-script-entry.log`。
