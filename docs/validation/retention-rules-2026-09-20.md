# 有期限的精确保留规则（Core 策略）

依据 `docs/01-product-ui.md` 设置页、P2-04 保护/忽略规则、P6-02 规则过期行为以及既有影响集合约束，新增 `ResidueCore/RetentionRules.swift`。仅纯值模型、Codable 校验与匹配策略，不读写文件、不增加系统调用或权限、不改 App/Persistence。

## API 与边界

`RetentionRule(id:recordIdentity:fingerprint:createdAt:lifetime:)` 为 throwing initializer。默认期限 30×86400 秒，最大 365×86400 秒；不是自动永久忽略。保存创建/到期时间及 UUID。`recordIdentity` 精确比较 providerID、scope、nativeIdentity，保留原大小写；不做目录前缀、glob、正则、同名软件或跨用户匹配。禁止通配符、控制字符、空或超长标识。fingerprint 必须是严格 64 位小写 SHA256 字符串，不能用空值/unknown 替代。

`RetentionRuleMatcher.evaluate(rule:observation:now:)` 返回 `protected`、`expired`、`notYetValid`、`unmatched`、`identityChanged`、`fingerprintChanged` 或 `unknownObservation`。到期时间点本身已失效。nil observation 是本轮未观察，不意味着已删除；未知 identity/fingerprint 不匹配。匹配结果只是此刻的纯函数判断，不记录以前的扫描或时间。若 UI 需要“曾观察到改变即永久撤销”的产品行为，必须显式更新规则存储；本函数没有隐含状态，也不声称抵御系统时钟任意回拨。

`RetentionRuleConfiguration(rules:)` 最多 128 条，拒绝重复 UUID 或同一完整 RecordIdentity 的多条规则。`encoded()` / `decode(data:)` 将完整 JSON 限制为 64KiB，schemaVersion 固定 1。日期固定编码为 Unix 秒数，不依赖调用方 date strategy。自定义 Codable 解码同样执行规则验证，并在逐条解码到第 129 条前拒绝；未知 schema、额外/缺失字段（包括嵌套 identity）、非法日期/期限不能绕过 public initializer。读取不执行任何导入动作；配置不是执行计划。

## UI/存储接线契约

只在用户明确选择当前已观察对象后创建规则，不自动添加，不隐藏行或影响对象。真实记录必须有可信采集路径产生的完整来源内容摘要；未知/解析失败且无摘要时不允许创建。独立合成 provider 可用于明确标记的演示测试，不能混作真实观察。

本项目当前 `contentSHA256` 是完整 plist 内容摘要，配合来源标识使用，**不是 inode/volume/mtime 等新鲜执行身份证明**。同一标识、相同内容被重新创建不一定可区分；规则只增加保护、不产生执行能力，所以不得拿此匹配替代 cleanup 最终指纹复核。将来若需要区分该场景，应由 provider 提供更强的、版本化的来源指纹，不能在 UI 猜测。

有效规则只能增加保护，例如将对应已存在 impact target 的 `isProtectedOrManaged` 设为 true；不能修改 presence、coverage、scopeBounded、capability，不能删去已展开的其他受影响对象。规则失效也不能解除其他来源的保护，应合并为 `existingProtection || retentionMatched`。过期是取消本条附加规则的匹配，不是触发清理或永久删除。

Core 未证明“用户确实点击过”或观察采集可信，调用方负责 UI 事件和来源验证。持久化边界、文件权限与防篡改由独立存储实现负责，此次没有写文件。

## 已运行测试

固定 Xcode 环境执行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueCore
```

完整 Core 40 项测试通过（0.434 秒）；其中新增 9 项边界/回归测试：provider/scope/native identity 独立不匹配，fingerprint 变化/缺失，精确过期边界和未来创建时间，非法范围/摘要/通配，Codable 往返与 Unix 秒，解码不能绕过验证，嵌套未知字段/schema，重复和条数/字节上限，以及实际 DryRunPlanner 保护集成。最后一项验证原来需要两次确认的完整影响计划增加保留保护后变 blocked，隐含影响对象和 presence 不变，digest 改变使旧确认不再适用。没有系统服务或文件修改测试。

## GUI 与本地配置集成

新增 `Features/Retention` 与 `ResiduePreferences`。详情中显式保留 30 天；记录仍显示原始存在状态、证据和覆盖范围。匹配后禁选，扩大影响中的受保护目标也会阻断计划。添加、移除、重新读取导致保护变化时清空既有选择/预演；扫描期间不允许更改规则，避免使扫描 generation 失效。合成演示规则只在内存，真实来源规则绑定来源身份和 plist 内容 SHA-256，写入本应用沙盒配置；内容 hash 不证明 inode 连续性或签名真实性。

后台 I/O 转发任务取消；读取失败明确报告未知，保存未确认要求重读，不自动覆盖。首次未配置读取不创建目录；只有明确保存才创建固定 Application Support 子目录。配置存储 22 项测试结果见[存储验证](preferences-storage-2026-09-20.md)。

2026-09-20 本轮重跑 `./script/test.sh core`：40 项通过（0.438 秒）。Debug 与 Release 构建成功；Release 签名检查验证 arm64/x86_64、App Sandbox、user-selected read-only、无调试 entitlement。Intel 未实际运行。

VM 实际 UI 正常路径：本地 Release 通过 NSOpenPanel 选择仅有自有 ISO01 的 LaunchAgents 目录；扫描返回 1 条，目标未授权保持“未能核实”。点击详情保留后显示“用户保留 · 禁止操作”，来源行仍可见；配置真实写入且 mode600。终止并重启自有应用后，“忽略规则”页重新读取到同一来源规则，在没有扫描的会话中显示“本次未观察到 · 不代表已删除”。这是沙盒 GUI 保存/跨进程读取证据，不代表源清理或系统服务操作。此 VM 包在后续取消转发及新沙盒父目录初始化修复前构建，后续改动须由最终构建/单测记录补充，不能视为已在 VM 重测。

首轮新增 UI 测试失败：侧栏恢复在底部导致 exists 但不可点击，以及 SwiftUI checkbox 的 value 非 String；已修测试为有界侧栏滚动、核验真实选择计数与预览门禁。后续运行结果待下文记录；首轮失败不计通过。

后续定向 GUI 运行：`xcodebuild ... -only-testing:ResidueGuardUITests/RetentionRuleUITests test`，2 项通过、0 失败（100.575 秒），分别覆盖完整保留/移除选择门禁和演示规则进程重启清空。最终 Preferences 重跑 22 项通过（2.011 秒）；取消转发和新沙盒初始化改动后的 Release 再构建及双架构签名检查通过。VM 中还实际点击移除本轮创建的本地规则，界面显示“尚无本地规则”，未修改夹具来源。

最终全量 `./script/test.sh ui`：18 项中 17 通过、1 系统 picker 显式跳过、0 失败（224.780 秒），包含新沙盒初始化改动。系统 picker 的 VM 手动界面控制证据独立记录，未把 XCTest 跳过改为通过。
