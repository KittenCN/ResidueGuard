# 事务未验证结果修复

2026-09-20，macOS 27 / 26A428，Xcode 27 / 27A266a，Swift 6.4。

审查发现 Core 协调器只验证动作主效果，未阻止 registration=unverified；首步可错误继续，末步可错误报告 completed。持久化 driver 已阻止该结果，因此两层判断分歧。

先新增 `uncertainRegistrationCannotCompleteEvenOnFinalStep`，修复前真实失败（5 个断言问题），分别覆盖首步及最后一步。现将完整结果判断集中为 `StepEffects.isVerified(for:)`，协调器与持久化 driver 共用；未验证登记状态均停止，不报告完成。pendingSystemRefresh 仍仅表示等待系统刷新，不证明历史登记已清除。

实际运行：`./script/test.sh core` 31 项通过；`./script/test.sh transactions` 6 项（含参数化）通过。日志留在忽略的 `.local-evidence`。这是合成事务协调层修复，不开启真实清理能力。
