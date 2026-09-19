# P3 / P4 纯逻辑准备结果

这些模块是后续 OS 适配器的可测试边界，不是已完成的清理功能。

## P3

`TransactionModels`、`TransactionCoordinator`、`RecoveryPolicy`：生产 gate 默认关闭且没有 production-enabled 枚举值；只接受 currentUser + synthetic-transaction-v1 profile。DryRunPlan 无法转换为真实执行授权。协调器要求独立事件、期限/摘要一致、全计划授权、全部备份先行、日志准备后再次校验；副作用失败停止，文件/服务/后台历史/权限分别记录。恢复只生成新的配置计划，不恢复旧授权、不自动加载服务。

10项合成事务/恢复测试实际通过，包括备份失败、日志失败、指纹改变、授权拒绝、作用域拒绝、重复 nonce/计划、取消、过期、意外额外效果、恢复冲突。Fake driver 记录调用顺序，未操作主机服务或配置。

**尚未实现/验证**：生产 driver、系统授权、真实备份/隔离/持久化 journal、TOCTOU 文件执行边界、服务卸载、崩溃补偿、隔离 OS 验收。协议中的 revalidate/verified 不是来自 GUI 的可信凭据，未来适配器必须独立获取证据。

## P4

`ResidueSecurity` 独立包：只允许版本化已知 ID/动作；没有 GUI 可传入的任意命令或路径接口。默认认证器返回不可用。纯策略要求精确 bundle/Team/requirement/uid/session/connection，绑定 token、plan digest、nonce、期限与已注册 server plan，拒绝版本、作用域、未知/保护影响及重放。成功返回 `reviewOnlyValidated`，执行可用性始终不可用。

`./script/test.sh security`：9项测试实际通过。包括同Team错误bundle/user/session/requirement、连接改变、篡改、过期/未来时间、重复token或同计划新token、未知/共享作用域、server plan变化和默认拒绝。

**尚未实现/验证**：真实 XPC 传输与签名握手、OS授权、helper 可执行与安装/批准/升级/卸载、root 文件操作、持久化 exactly-once journal、隔离攻击测试。内部 token 仅内存模拟，重启失效，不是生产持久执行令牌。

没有可回滚测试环境和有效签名身份，不能把上述单测计入 P3/P4 OS integration passed。测试命令使用项目固定 Xcode27.0；核心包合并测试结果见最终报告。
