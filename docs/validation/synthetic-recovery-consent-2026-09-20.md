# 自有恢复新计划与双确认：合成模型验证

本轮只增加 `Packages/ResidueRecovery/Sources/ResidueRecovery/SyntheticRecovery.swift`、对应测试与本文。不修改现有RecoveryAudit导入模型、Core确认状态机、VM probe、生产gate或执行器；没有路径参数、文件读取、运行时采集、恢复动作、证书或helper。

## 为什么不直接复用 Core ConsentSession

已阅读Core `ConsentSession.swift` 和 `Planning.swift`。其安全结构包括独立presentation UUID、步骤顺序、摘要与过期检查，可以作为语义参考；但它必须接收由清理DryRunPlanner构造的DryRunPlan，并硬编码清理风险短语。为了用于恢复而伪造清理能力/profile或扩展现有生产规划器，会模糊边界。因此新增小型独立合成模型，保持Core API完全不变；未来真实确认接线仍需重新审查，不能把本模型改个名字作为凭证。

## 精确范围

- `SyntheticRecoveryAssessment` 只接收六域SHA256（原位置不存在证据、隔离对象、backup、程序、运行时、根目录）及观察时间。所有值都是调用者提供的合成输入，不是fresh文件验证。UUID由模型产生，没有历史审计转入接口。
- `SyntheticRecoveryPlan` 每次产生新UUID，摘要包含固定操作/策略语义、新计划与assessment UUID、全部证据和时间。有效期截止assessment观察后120秒；晚生成计划不会延长证据寿命。拒绝非finite时间、未来/过期assessment、非规范hash。
- `SyntheticRecoverySession` 为MainActor引用类型，使同一会话的消费串行且不能靠复制value重放。presentFirst→acceptFirst→presentSecond→acceptSecond均须独立方法调用；两个presentation有独立nonce/ordinal/plan绑定。第二次要求精确风险短语“恢复仍安装软件的启动配置”。不接受confirmed Bool。
- presentation/consent无public构造器、不实现Codable，不可从历史文件或JSON反序列化。它们仍**不是人类确认的证明**；测试代码能合法驱动所有合成事件。receipt只允许其产生会话单次消费，跨会话拒绝。消费只返回合成结果，不执行动作。
- 任意错误事件、变更assessment、时间倒退、到期、取消均使会话失效。换计划丢弃旧事件和receipt；每会话最多见过64个计划，不接受同一计划UUID重新引入。一次消费保证仅限这个内存会话，不是跨进程持久化防重放机制。
- assessment、plan、presentation、consent、session、消费结果均公开 `permitsMutation=false`。该模块不依赖Backup/Quarantine/Platform/Persistence执行能力，也不把RecoveryAudit的数据当成授权。

## 实际测试

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueRecovery`：完整包 **20项Swift Testing通过**，其中本轮新增10项，原历史审计测试保持。日志 `.local-evidence/synthetic-recovery-tests.log`。新增覆盖完整合成流程且所有artifact拒绝mutation、六域变更、非finite/非法摘要、120秒边界、错短语、乱序、同事件冒充二次确认、跨会话事件和receipt、取消、替换计划、禁止重新引入旧计划及重复消费。环境macOS27.0/26A428 arm64，Xcode27.0/27A266a。

开发中首次误写已有包清单导致缺少ResidueCore依赖的链接失败，已将清单精确恢复原内容；最终清单无diff，完整包重跑通过。该失败不计作通过。`git diff --check`通过。本轮没有运行VM、GUI、真实恢复或任何服务操作。

## 尚未完成，不能据此宣布恢复可用

没有fresh fd锚定文件/manifest/元数据校验，没有已验证运行时证据，没有真实影响预览UI或实际用户两次确认，没有持久化单次attempt/intent、执行前最后重核、真实rename、后验或崩溃恢复。

下一步可独立实现固定自有VM夹具的**只读**fresh assessment采集器及恶意临时夹具矩阵；采集器应生成另一种受限事实类型，不能接收本文件的合成hash当作验证事实。随后才考虑真实UI确认与执行边界。实际用户确认验收需要用户看到具体新计划并完成两次独立操作；自动测试应继续明确标识synthetic，不伪称人类确认。第三方清理/恢复gate保持关闭。
