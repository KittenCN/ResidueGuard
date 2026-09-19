# ResidueSecurity — P4 契约与纯策略准备

这是可独立测试的 **helper 协议契约及服务器端策略模型**，不是特权 helper，也没有在主应用中启用。没有 XPC 服务、ServiceManagement 注册、启动服务、提权、文件修改或系统权限重置代码。

请求只接受版本、已知来源 ID、计划/备份/执行 ID 与一次性 token。没有任意路径、命令、可执行文件、写入内容或删除接口。来源 ID 必须映射到服务器自己建立的计划，GUI 不能注册该计划。

`CallerAuthenticating` 是未来经过实际签名握手验证的 transport 边界。默认 `UnavailableTransportAuthenticator` 始终拒绝；`VerifiedCaller` 构造器仅模块内部可用，不可由 GUI 自报身份创建。纯策略同时检查 bundle、Team、designated requirement、UID、session；token 还绑定原始连接身份。字符串比较本身不执行代码签名验证：没有已验证的 SDK/XPC 身份适配器，就没有生产身份认证。

令牌绑定来源、作用域、计划摘要、协议/策略版本、nonce 与 120 秒截止时间；服务器当前时间在认证返回后读取。内存账本拒绝 nonce 重放和同一计划的第二个 token。共享机器作用域、共享/受保护/未知影响被阻断。只有服务器模型中的明确当前用户影响可以得到 `reviewOnlyValidated`；该结果不是产品确认、系统授权、备份、身份重验或执行许可。`executionAvailability()` 永远返回 `authorizationUnavailable`。

尚缺且不能标记通过：签名应用/XPC audit 身份绑定、macOS 授权权利、signed helper 安装审批、持久防重放/崩溃日志、服务器现场源指纹和完整影响展开、隔离系统攻击测试、实际执行与恢复。当前 token 不持久化；进程重启全部 token 失效，不能声称跨崩溃 exactly-once 执行。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueSecurity
```

测试使用 `@testable` 合成 transport 身份，只验证纯策略；它不是对生产 XPC 或操作系统认证的测试。
