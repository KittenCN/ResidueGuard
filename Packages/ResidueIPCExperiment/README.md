# ResidueIPCExperiment

独立的真实 XPC 代码签名约束实验，不是产品 helper。无特权、无安装步骤、无 LaunchAgents/Daemons 配置或系统级 Mach 服务注册。唯一 IPC 方法是不接收输入的 `pingWithReply`，固定返回 `pong-v1`。不接入 ResidueSecurity，不生成 VerifiedCaller，不开放任何清理。

Foundation 公共 API `NSXPCConnection.setCodeSigningRequirement` 在 macOS 13+ 可用；本包 minimum macOS 14。client 和 server 的 incoming connection 均在 resume 前配置 requirement，不读私有 auditToken、不使用 KVC、不用 PID 充当签名校验。server 另核对 connection.effectiveUserIdentifier 等于自身 uid，拒绝 root 启动。

## 构建与运行

```sh
python3 Packages/ResidueIPCExperiment/script/build_lab.py
python3 Packages/ResidueIPCExperiment/script/run_lab.py <上一步生成的 ipc-lab-UUID 目录>
```

固定使用已安装 Xcode。构建器仅创建包内忽略的 `.build/ipc-lab-UUID`，输出四个临时 `.app`（纯 CLI bundle 用于发现内部私有 `.xpc`，不含 GUI/AppKit）：

- accepted：精确客户端和服务端 cdhash，固定 ping 成功。
- rejected-client：不同 ad-hoc bundle identifier 签名的客户端，server 仍要求原客户端 cdhash，拒绝。
- wrong-server：正确客户端但要求错误服务端 cdhash，客户端拒绝响应。
- accepted-alternate-control：另一独立客户端、server 使用其正确 cdhash，ping 成功。额外第五步对同一个 rejected-client.app 只替换外部 harness pin 后再请求，须返回 pong-v1，排除其本身无法启动造成的假阴性。

宿主脚本直接调用 CLI bundle 内 executable 捕获退出状态。若客体验证，复制生成目录到专用 VM share，在客体 `bash <directory>/run_vm_lab.sh`。它只在非 root VirtualMac 运行，把四个 app 复制至唯一新建的当前用户 Applications 子目录，使用 `open --background --new` 启动 bundle，并分别验证准确输出及两个自有 executable 路径的进程退出；结果写 share 下 `ipc-vm-results.txt`，不覆盖旧结果。client 等待最多 5 秒，server 最迟 8 秒退出，启动器等待及结果/自有进程退出各自 12 秒上限。无常驻轮询；运行完成后可移除这些自有测试 bundle。

## 明确的实验限制

本次按内到外签署完整 `.xpc` 与 `.app`，并在 ditto 复制到全新目录后再次 `codesign --verify --deep --strict` 验证完整资源 seal。原 standalone Mach-O 签名组装进 app 的方案在 VM 和宿主均严格验证失败，已弃用，不能把过去裸可执行文件的签名验证当成 app 验证。

为消除双向 cdhash 与资源 seal 的循环依赖，最终签名完成后生成 lab 外部 `peer-requirements.plist`，仅作为受控实验 harness 输入。它不在 app 资源 seal 内，不是生产信任根；恶意修改它可以改变实验信任配置。对端不能经 ping 接口传入 requirement，但这不足以保护本地 manifest。正式方案须采用编译常量与稳定证书身份，参见 `docs/validation/local-signing-design.md`，此处没有创建或导入任何证书。

cdhash 是当前二进制/签名的精确身份约束；重新构建/重签名会改变它，旧 requirement 必须拒绝新构建。它不证明 Apple Developer/Team 身份、发布者身份或完整 bundle 资源身份，也不验证 privileged helper 安装、授权、会话绑定、抗重放和清理接口。没有放宽现有 HelperPolicy。

SDK 对 `NSXPCListener.setConnectionCodeSigningRequirement` 的注释明确禁止用于 serviceListener，因此服务使用 accepted connection 的公开 setter；没有调用会触发 assertion 的 listener setter。anonymous listener endpoint 需要通过已有 XPC connection 传送，本实验没有伪造文件序列化传 Mach 端口。

实测：macOS 27.0 / 26A428 专用 VirtualMac 第三轮五场景全部通过，各自确认精确自有进程退出。前两轮打包及 open 等待竞态失败与修复见 `docs/validation/ipc-transport-experiment-2026-09-20.md`。
