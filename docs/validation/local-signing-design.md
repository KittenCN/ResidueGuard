# 本地稳定开发签名设计（待 VM 验证）

日期：2026-09-20。本文只完成官方资料及本机 SDK/man/help 的只读核对；**未创建证书、私钥或 keychain，未导入身份，未修改信任设置，也未运行下述签名命令**。现有 ad-hoc XPC 实验结果不等于本方案已验证。当前开发不需要先取得 Developer ID 或 App Store 资格。

## 推荐方案：隔离客体内固定自签证书 + 双向证书 requirement

在可恢复的专用 VM 内创建一个专用代码签名证书及临时 keychain，在这一轮开发/重建实验中保留同一身份。client 与 server 分别使用不同、固定的 signing identifier。各自把对端 requirement 编译成只读字符串常量，而不是从未验证 plist、环境变量或 IPC 参数读取。

拟采用的 requirement 形状为：

```text
certificate leaf = H"<本轮固定自签证书DER的SHA1指纹>" and identifier "example.residueguard.localdev.client"
certificate leaf = H"<同一证书DER的SHA1指纹>" and identifier "example.residueguard.localdev.server"
```

单一自签证书同时为 leaf/root，也可写 `anchor = H"..."`。本方案优先 leaf 精确匹配，避免将来换成 CA 层级时不经意接受该 CA 签发的所有证书。SHA1 是 requirement 语言定义的证书标识格式，并非要求采用 SHA1 签发证书；证书本身应使用 SHA256 签名。不要用同名 CN、任意 OU、identifier 单独匹配或 `anchor trusted` 代替精确证书约束。Apple 说明自签证书和 ad-hoc 的 requirement 语义不同，后者没有证书链。[Code Signing Requirement Language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)

双向常量只取决于证书与 identifier，不取决于本次 Mach-O cdhash。双方代码、Info.plist、资源完成后，先签内部 `.xpc`，再签外层 `.app`；这样没有当前实验的循环 cdhash 依赖。重新构建后 cdhash 可以变，固定身份 requirement 仍应匹配；更换证书或 identifier 应拒绝。自签证书只能证明由该私钥签署，不能证明真实组织、Apple Team 或外部发布者身份。[TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

## 准备身份：仅在未来专用 VM 执行

1. 确认 hw.model=VirtualMac*、非 root、基线可恢复。私钥和 keychain 只能在 VM 本地 0700 实验目录，不能放共享目录、仓库、日志或截图。
2. 保存客体原用户 keychain search list。创建独立 keychain，不改 default keychain，不导入登录/系统 keychain。
3. 优先通过客体 Keychain Access 的 Certificate Assistant：Create Certificate → Self Signed Root → Code Signing，覆盖默认设置并明确保存到实验 keychain。证书名称使用本轮随机标识；当前系统 UI 是否允许直接选目标 keychain 必须实查。如工具只能写 login keychain，则停止此路线，改用下述导入路线，不能默默污染 login keychain。
4. 不添加系统根信任、TLS trust、Always Trust 或 `security add-trusted-cert`。显式证书 requirement 的验证与系统“信任该证书”不同。若本机签名器仍报链/用途错误，应保存脱敏错误并定位证书扩展、链和 keychain 搜索路径，不通过全局信任放宽来制造成功。

Apple 的 Certificate Assistant 流程明确支持 Self Signed Root + Code Signing 用于内部开发，并要求先签 nested code 再签外层资源。[Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)

以下命令是**待执行模板**，变量由未来 VM runner 使用受控绝对路径填写。这里不包含密码。`security ... -P/-u` 使用系统安全输入界面，可能需要人在客体输入/批准；不能把用户给出的登录密码放入 argv、shell history 或文档。

```sh
security list-keychains -d user
security create-keychain -P "$LAB_KEYCHAIN"
security unlock-keychain -u "$LAB_KEYCHAIN"
```

替代导入路线：在 VM 本地生成带 codeSigning EKU、digitalSignature KeyUsage、SHA256 签名的自签证书和**加密**私钥；以加密 PKCS#12 导入实验 keychain。可使用当前系统 OpenSSL/LibreSSL（先检查客体是否已有，不自动安装）。配置扩展和 CA flag 需按本机签名器验证，不把通用 TLS 证书当代码签名证书。使用交互式口令，不使用 `-nodes`、argv 密码或 `-A` 全应用私钥访问。准确可用的导入命令为：

```sh
security import "$LAB_P12" -k "$LAB_KEYCHAIN" -f pkcs12 -x -T /usr/bin/codesign
```

这是更可控的自动化方向，但本轮未验证证书生成参数，故不提供看似已验证的一键生成脚本。`-x` 请求导入后不可导出私钥；输入 P12 本身仍敏感，导入验证后清理其副本。Certificate Assistant 路线可避免私钥额外落盘。独立 keychain 的密码不要复用 VM 登录密码。

本机 `security help` 已核实 create-keychain -P、unlock-keychain -u、import -k/-x/-T。不要默认运行 `set-key-partition-list`；它改变密钥访问策略，且密码参数可能暴露。若 codesign 出现 key ACL 提示，仅批准 `/usr/bin/codesign` 对这个实验私钥的必要访问；拒绝时记录不可用，不退化成任意应用可访问。

## 构建、签名与验证命令模板

本机 `man codesign` 说明 `--keychain` 限定身份搜索，但链构造仍用用户 search list；必要时**只在 VM**将实验 keychain 加到已完整保存的列表末尾，结束后精确恢复原列表，不把列表替换成仅实验 keychain。使用完整证书 SHA1 指纹作为 `--sign` 参数，避免同名身份歧义。

```sh
security find-identity -p codesigning "$LAB_KEYCHAIN"
# 公开DER证书可用于requirement；私钥不可导出到构建共享目录。
security find-certificate -c "$LAB_CERT_NAME" -p "$LAB_KEYCHAIN" > "$LAB_CERT_PEM"
/usr/bin/openssl x509 -in "$LAB_CERT_PEM" -outform DER -out "$LAB_CERT_DER"
/usr/bin/openssl x509 -in "$LAB_CERT_PEM" -noout -fingerprint -sha1

# 先把固定对端requirement编译进双方，再组装完整bundle；下列无 --deep 签名。
codesign --sign "$LAB_CERT_SHA1" --keychain "$LAB_KEYCHAIN" --timestamp=none \
  --identifier example.residueguard.localdev.server \
  -r="designated => certificate leaf = H\"$LAB_CERT_SHA1\" and identifier \"example.residueguard.localdev.server\"" "$LAB_XPC"
codesign --sign "$LAB_CERT_SHA1" --keychain "$LAB_KEYCHAIN" --timestamp=none \
  --identifier example.residueguard.localdev.client \
  -r="designated => certificate leaf = H\"$LAB_CERT_SHA1\" and identifier \"example.residueguard.localdev.client\"" "$LAB_APP"

codesign --verify --strict --verbose=4 "$LAB_XPC"
codesign --verify --deep --strict --verbose=4 "$LAB_APP"
codesign --display -r- "$LAB_APP"
codesign --verify --strict -R="certificate leaf = H\"$LAB_CERT_SHA1\" and identifier \"example.residueguard.localdev.client\"" "$LAB_APP"
```

`LAB_CERT_SHA1` 是已校验恰好 40 位十六进制的公开证书摘要，不是密码。预先用 `csreq`/Security requirement parser 编译 requirement 并在错误时停止。`--timestamp=none` 明确离线，不调用 Apple 时间戳服务。上面在新 staging bundle 上签名，不覆盖任何用户 app。

完整资源 seal 的静态验证与 NSXPC 动态 peer requirement 是两项不同验收。签名成功或 `codesign -d` 有输出都不代表验证成功；NSXPC 收到签名匹配的消息，也不代表它递归验证了所有 bundle 资源。当前 SDK `SecStaticCode.h` 提供 `SecStaticCodeCheckValidityWithErrors`、`kSecCSStrictValidate`、`kSecCSCheckNestedCode`，可用于单独检查完整本地包，但不能用一个路径检查结果替代当前连接的动态身份。本方案将信任常量编译进 executable，因此运行中的信任决策不依赖 mutable requirement plist。

## 下一轮最低真实验收矩阵

- 两端完整 seal 验证成功，正确证书+正确 identifier 的真实 XPC ping 成功。
- 同证书、错误客户端 identifier 被拒；另一自签证书、相同 identifier 被拒；ad-hoc 同 identifier 被拒。
- 客户端要求错误 server certificate/identifier 时拒绝；正确替代身份正向对照成功，排除通用启动失败。
- 修改客户端/服务端 Mach-O、Info.plist、一个普通资源、替换 nested XPC，各自独立副本的 strict 校验失败。运行时拒绝行为另测并如实记录，不把静态失败推成运行时必然拒绝。
- 用同一个保留的实验身份重建 V2：cdhash 变化，原证书+identifier requirement 仍接受；重签为另一证书的 V2 拒绝。
- 锁定/删除实验 keychain 后，已有签名的 requirement 验证与执行结果分别观察；不能把“无法继续签名”和“旧签名不可验证”混为一谈。
- 双端进程按界限退出，无 helper、Mach service、系统信任项或隐私授权残留。恢复客体 keychain search list，删除专用 keychain和私钥副本；需要跨任务保留开发身份时先明确保存方案，不误删唯一私钥。

Gatekeeper、hardened runtime、library validation、SMAppService 注册/用户批准、特权授权、会话约束和升级撤销仍是独立系统机制。自签身份不是这些能力的通行证；出现限制不禁用 SIP/Gatekeeper、不移除 quarantine 以绕过验收，也不把任意 entitlement 当作已获系统授权。Apple 明确区分稳定代码身份和 Gatekeeper 接受条件。[Understanding the Code Signature](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/AboutCS/AboutCS.html)

## 不创建证书的替代路线及局限

可以先把 requirement 固定在 executable 编译常量中，做**单向**本构建 cdhash 的 transport 验证，并完整签封各个实验 bundle；这能移除当前未密封 plist 作为信任输入的问题。它仍然不自动形成双向稳定身份。

若 client 只信任“自己已验证完整签名的 bundle 内 server”，则必须明确静态包校验、取预期 server cdhash和连接动态 requirement 的每个步骤，并处理本地替换窗口。server 若仅验证 client identifier，对 ad-hoc 客户端可被仿造；若改成固定 client cdhash，而 client 的外层 signature 又涵盖含该常量的 server，则重新出现构建依赖循环。不能通过不验反向身份、跳过资源 seal、允许通配 identity 或信任任意本地配置来宣称循环已解决。

因此这条路线适合延续只读 ping 技术实验，不宜升级为产品 helper 的认证根。推荐证书方案以本轮稳定证书身份打破循环，并将 certificate-pin/identifier 双向验证、完整 seal 和真实 XPC 攻击矩阵作为独立证据。

## 用户是否需要做事

本轮无手工前置要求。下一步可先自动完成 VM gate、已有工具核查、构建器改造和非敏感检查。真正创建独立 keychain/证书时可能出现安全口令或私钥访问界面；如自动化不能安全处理，需要用户仅在**客体**完成该具体输入/批准，不需要购买 Developer ID、不需要修改宿主信任。当前没有验证任何此类界面必然出现，因此不能把它们提前列成已确认阻塞。
