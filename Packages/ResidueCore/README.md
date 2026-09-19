# ResidueCore (P1)

Swift 6 / macOS 14+ 纯策略库。无 SwiftUI、Process、系统扫描或执行器；没有授权真实写操作的 API。

- `SourceRecord` / `ProviderResult`：保留作用域限定身份、原始来源、解析警告与覆盖；来源失败不能伪装为空扫描成功。
- `OrphanClassifier`：高可信残留需要完整覆盖、明确身份、所有目标缺失、稳定复核和证据；离线、权限不足、废纸篓、共享活跃、安装中、运行反证均阻止标红。
- `DryRunPlanner`：先合并同一底层操作的所有影响，再检查每项精确能力、OS build、身份/指纹、保护状态和范围。冲突、未知、缺失和过期均阻断。
- `ConsentSession`：独立呈现事件，一次/两次确认、第二次风险短语、到期和摘要变化失效；完成只代表 dry-run 演示结束。

能力、存在证据和指纹由调用方提供，仅用于 P1 合成测试。未来真实写入不能信任这些输入，必须独立重新验证来源、影响集合、签名、备份和授权。`supportedVerified` 合成 profile 不是 macOS 集成验证。

根目录运行 `bash script/test.sh`。测试读取根 `fixtures/confirmation-cases.json` 的 F01–F24，另外覆盖影响扩展、去重/冲突、过期、重装指纹、独立确认/重放、能力维度和保守存在性。CLT 环境可能缺少 Swift Testing 插件，使用项目固定完整 Xcode。
