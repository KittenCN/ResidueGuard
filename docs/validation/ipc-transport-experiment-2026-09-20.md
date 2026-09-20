# 无特权 XPC transport 代码签名约束实验

环境：macOS 27.0 / 26A428 arm64，Xcode 27.0 / 27A266a；未安装或启动产品 helper，没有修改宿主 LaunchAgents、LaunchDaemons、TCC 或 BTM。新增独立 `Packages/ResidueIPCExperiment`，仅 Foundation 固定 ping 接口。Objective-C 仅用于最小 Foundation API 实验，不改变产品 Swift 6 架构。

当前结论：第三轮真实 VM 的五个 XPC 场景已全部通过，且精确自有进程退出；前两轮打包/等待失败及修复完整保留如下。此结果仅覆盖受控无特权 transport 实验。

## API 核实

本机固定 Xcode SDK `Foundation.framework/Headers/NSXPCConnection.h`：`setCodeSigningRequirement` 和 listener setter 从 macOS 13 开始公开；后者只接受 anonymous/Mach listener，对 serviceListener 调用会 assertion。实验在 `shouldAcceptNewConnection` 中使用前者并且先配置再 resume。[Apple setter 文档](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:)) 给出这种 incoming-connection 配置示例。

[Apple endpoint 文档](https://developer.apple.com/documentation/foundation/nsxpclistenerendpoint) 说明 endpoint 经已有 NSXPCConnection 发送。因此没有尝试将端口写入普通文件冒充跨进程传输；本实验使用临时 app 的内部私有 XPC bundle，既不安装系统服务，也不请求提权。

## 初轮宿主 transport 结果（打包缺陷见后文）

构建：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path Packages/ResidueIPCExperiment` 成功。`python3 Packages/ResidueIPCExperiment/script/build_lab.py` 生成唯一目录并对 standalone Mach-O ad-hoc 签名、strict codesign verify，获取本构建实际 cdhash。`run_lab.py` 执行真实跨进程 ping：

| 场景 | 结果 | 退出 / NSError code |
| --- | --- | --- |
| 正确客户端、正确 server requirement | pong-v1 | 0 / 0 |
| 不同 ad-hoc 客户端，server 保持原 cdhash | 无响应、无 timeout | 3 / 4097 |
| 正确客户端，错误 server cdhash | 无响应、无 timeout | 3 / 4102 |
| 不同客户端 + 匹配该客户端 cdhash 的对照 | pong-v1 | 0 / 0 |

四个 case 均满足脚本断言，stderr 为空；随后检查没有自有 IPCExperimentClient/Server 残留进程。两条正向对照支持拒绝来自 requirement 差异，而不是通用启动失败。上述错误码仅为本机实际观测，不宣称跨系统稳定 API。客体 runner 另提供 VirtualMac/non-root gate，以 open 启动纯 CLI bundle、校验脱敏输出并写 shared evidence；三轮客体验证结果及中间失败见后文。

## 不能据此推断的结论

原始方案签名仅覆盖 Mach-O，后续发现组装后 strict 失败；该失败和完整封包修复见下节。当前 bundle 资源已签封，但外部 requirement manifest 仍只是实验构建器生成的受控输入，不能搬作生产信任来源。此实验只证明本构建/本系统上的 transport code requirement 可区分两个真实 ad-hoc 签名二进制。重新构建或重签名导致 cdhash 更换，旧约束应拒绝，不能把通配 requirement 作为兼容补丁。

没有 Developer/Team 身份、完整 bundle 信任链、稳定开发签名 profile、session binding、privileged helper 授权/安装/生命周期、token 抗重放或清理能力的集成证明。现有 ResidueSecurity 默认 UnavailableTransportAuthenticator 和 mutation gate 完全不变。

## 首轮 VM 打包失败与修正（保留失败证据）

首轮客体在启动前 `codesign --verify --strict` 失败：`code has no resources but signature indicates they must be present`。随后在宿主原 `.app` 内同样复现。根因不是 ditto 丢失文件，而是先对 standalone Mach-O 签名再放入 bundle，codesign 在 bundle 上下文中发现没有完整资源 envelope。此前的 strict 成功只发生在组装前独立 executable；它不能证明组装后 app 签名完整。初轮宿主 ping transport 观测仍真实，但不能称那个实验包完整签封。

修复后的构建器先组装，再显式签完整 nested `.xpc`，最后签完整外层 `.app`。每个包立即 deep/strict 验证，再用 ditto 复制整个 lab 到新目录，重复全部 strict 验证与真实 XPC 用例，成功后才删除验证副本。独立篡改 Info.plist 的副本验证失败，确认 resource seal 检查实际生效。

为避免双向 cdhash 与封包的循环依赖，peer requirements 改为所有包签完后生成的外部 `peer-requirements.plist`。**包已完整签封不等于此 manifest 可信。**它只是受控实验 harness 配置，本地攻击者可改变它；不应用于产品信任决策，未接入 ResidueSecurity。稳定证书 + 编译常量方案仅记录于 `local-signing-design.md`，还没有创建任何身份。

修复后已在宿主新复制目录验证：accepted pong；rejected-client none/4097；wrong-server none/4102；accepted-alternate-control pong；并对**原来同一个 signed rejected-client.app**只替换外部 harness pin 后得到 pong，排除其启动失败造成的假阴性。四种包都保留 strict 签名，无修改包内配置。VM runner 使用独立输出文件记录第五步，仍要求新共享目录、VirtualMac、非 root；后续第三轮客体实际结果见末节。

## 客体快速重开 race 与等待机制修复

第二轮客体完整 seal 验证通过，前四个实际 XPC case 符合预期。第五步快速重开同一客户端时，`open --wait-apps` 自身报 `Unable to block on applications (initial call to kevent() failed: No such process)`，使严格脚本提前结束。该轮不计完整通过。

根因是 `open -W` 注册进程等待与快速 CLI 退出之间的竞态，并非允许忽略启动器错误。修复新增共用 `launch_case.sh`：用 `open --background --new` 仅请求启动，严格检查启动器退出码；之后独立等候全量预期输出、空 stderr，并用 `ps -ww -axo pid=,comm=` 验证本次两个精确自有 executable 路径都已退出。ps 失败也直接失败；没有输出、错误输出、stderr、进程未退出都有有界失败。没有把任意非零退出码当作可忽略 race，也不凭存在一个旧输出文件认定成功；输出文件必须原先不存在。

启动器最多等 12 秒，超时只终止本脚本启动的 open PID；结果/精确自有进程退出另有 12 秒界限。Client/server 原有 5/8 秒自限不变。不用模糊名称杀进程，不影响用户 app。`--background` 避免抢占前台 GUI。

此次未运行 Xcode/编译。宿主以新启动函数连续五次重开同一个 signed rejected-client（匹配 pin）均 pong 且自有进程退出；另四个原始 case 全部通过相同输出/退出检查。新 runner 已通过 bash -n。生成新的 lab 副本，完整资源签名未变，deep/strict 再次验证通过；第三轮 VM 已实际执行通过，见下节。

## 第三轮真实 VM 验证：全部五场景通过

已读取本地证据 `.local-evidence/vm-transfer/ipclab3/ipc-vm-results.txt`。客体为本任务使用的 macOS 27.0 / 26A428 VirtualMac；脚本通过非 root/VirtualMac gate，完整 bundle 签名验证后执行全部场景：

| 场景 | 实际 reply / errorCode | 精确自有 client/server 进程退出 |
| --- | --- | --- |
| accepted | pong-v1 / 0 | true |
| rejected-client | none / 4097 | true |
| wrong-server | none / 4102 | true |
| accepted-alternate-control | pong-v1 / 0 | true |
| 同一个 rejected-client 更换为匹配的外部 pin | pong-v1 / 0 | true |

全部 timeout=false，结果文件最后明确记录 `PASS transport-experiment-only teamIdentity=false bundleResourceSeal=true harnessManifestTrustedForProduction=false mutation=false`。这证明新等待机制在真实客体完成同一二进制快速重开的正向对照；不能扩大为 Team 身份、生产信任根、特权 helper 或任何清理能力已完成。前两轮失败证据保留在忽略的本地目录，没有覆盖或删除。

提交前静态检查：两个 Python 脚本通过 AST 语法解析、两个 shell 脚本通过 bash -n，git diff --check 通过；包内待提交文件只有源码、Package.swift、README 和构建/运行脚本，`.build` 实验包和原始客体证据未纳入 git。
