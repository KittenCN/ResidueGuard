# P4 HelperRequest 有界规范 wire codec

新增 `HelperRequestWireCodec` 与独立攻击矩阵测试；没有修改现有 Contracts、HelperPolicy 或信任配置，也没有接入 GUI、XPC、executor、authenticator。`decode` 返回的 HelperRequest/PlanToken 仍是未受信输入，不能生成 VerifiedCaller，不能建立来源计划，不能绕过默认 transportUnavailable 或 authorizationUnavailable。

## 格式与兼容性

v1 frame 是 `{ "wireVersion": 1, "request": <既有 HelperRequest Codable 结构> }` 的唯一规范字节形式。编码固定 sortedKeys、withoutEscapingSlashes、deferredToDate；日期值是 Foundation Date 参考时刻 2001-01-01 00:00:00 UTC 起的秒数。没有更改现有 DTO 自身的 Codable 行为，也不自动接受旧的裸 HelperRequest JSON。status 固定 golden frame 有字节级测试。

解码先限制资源，再由 JSONDecoder 校验类型，验证 wire/protocol/policy 版本与 token 字段，最后重新规范编码并要求字节完全一致。因此重复字段、未知字段、不同转义、冗余空白、其他数字写法、尾随内容等全部拒绝。UUID 与枚举只接受规范重编码后的字节，不能借未知 path/command 字段夹带扩展。digest 仍保持现有允许 ASCII hex 大小写的语义，不悄悄改写 token。

这是本 codec 的封闭 v1 格式，**不是 RFC 8785 的通用跨语言 canonical JSON 实现**。Foundation 数字编码或 Swift synthesized enum 结构未来变更时必须通过明确版本升级及 golden/跨版本验收；不做自动宽松回退。当前尚未部署真实 transport，因此没有既有线上 frame 迁移或兼容承诺。

## 有界输入与语义边界

- 整帧最多 16,384 bytes，空输入拒绝。现有全部请求种类的实际规范帧均小于 1 KiB，测试断言此余量；上限不授权增加字段。
- 调用 JSONDecoder 前只做资源扫描：嵌套最多 8 层、最多 64 个字符串、每个字符串最多 256 个原始编码字节（含转义）。超限直接 resourceLimit，不先构造解析对象。扫描器正确处理转义引号/反斜线，JSON 语法仍由 JSONDecoder 决定。
- wire/protocol/policy 版本仅 1。token digest 恰好 64 个 ASCII hex；expiry 的参考日期和 Unix 秒数都必须 finite。
- UUID、已知操作/source kind/scope 由既有有限 DTO 解码。sharedMachine 可以传输，但现有 policy 仍拒绝；codec 不冒充授权策略。
- 是否过期、nonce 是否已消费、计划是否存在、连接身份是否变化，由现有 HelperPolicy 后续检查。codec 不替调用者确认或 OS 授权。

## 实际验证

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueSecurity` exit 0：**23 项通过**（原策略 11 + wire 12），0 失败。日志 `.local-evidence/security-wire-codec.log`。环境 macOS 27.0/26A428 arm64、Xcode 27.0/27A266a。

新增覆盖：全部请求类型往返、status golden frame、整帧/深度/字符串数量/字符串长度上限、未知与重复字段、非规范空白/转义/数字/尾随垃圾、未知版本、坏 digest、NaN/正负 Infinity expiry、恶意数字溢出、非法 UUID/scope、无效 UTF-8/截断/错误形状，以及解码后的 token 仍被不可用认证器拒绝、执行 gate 仍关闭。

此结果仅是纯解析/策略测试，不是 XPC 身份认证、helper 安装、权限修改或 VM 实验。下一步可在独立无特权 transport 实验中接入有界 status/review-only frame，并记录真实连接失效/跨连接拒绝；不能把解析成功视为认证成功。
