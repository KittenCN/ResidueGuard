# 08｜公开来源、证据强度与架构决策

研究日期：2026-09-20。网页可能更新，实施前应重新核对与目标 OS build 的对应关系。本文件区分官方能力声明、官方历史资料、开发者一手问题报告和本项目设计选择。后两者不能冒充 Apple 的通用保证。

## 8.1 来源索引

### [S01] Apple Platform Deployment：Manage login items and background tasks
来源：`https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web`

用于确认 BTM 诊断、后台登记与系统设置的关系；可查看状态的工具与全量重置是不同操作。系统管理文档不意味着普通第三方 app 获得任意逐项删除 API。本文据此选择诊断读取 + 精确来源清理，不把全局重置混入行级操作。

### [S02] Apple Developer：SMAppService
来源：`https://developer.apple.com/documentation/servicemanagement/smappservice`
补充：`https://developer.apple.com/documentation/servicemanagement/updating-your-app-package-installer-to-use-the-new-service-management-api`

用于确认自身 app bundle 内服务的生命周期接口与系统设置入口。不是全系统应用管理器。具体 helper 集成需本机 SDK、签名和授权实验。

### [S03] Apple Developer：macOS 27 release notes，TCC
来源：`https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes`
官方文档数据：`https://developer.apple.com/tutorials/data/documentation/macos-release-notes/macos-27-release-notes.json`

关键条目编号 90775556：应用不能再直接访问本地 TCC 数据库。这是本项目不能将旧读库方案作为新系统基础的直接依据。研究时网页缓存出现不同 beta 标题，因此本方案不宣称某个 beta 是当前最终稳定版；限制以已读取的官方条目为依据，发布前复核最终目标系统。

### [S04] Apple Developer Forums：Restricted TCC.db access — permissions check in real time
来源：`https://developer.apple.com/forums/thread/833806`

Apple Security 工程师答复指出可查询的权限状态应使用其所属框架的 API，无对应 API 时提交反馈。这里没有提供全系统第三方应用权限枚举接口。本文不把“查询本应用状态”扩展解释成“查询所有应用授权”。

### [S05] Apple Developer Forums：tccutil: Failed to reset microphone
来源：`https://developer.apple.com/forums/thread/679303`

Apple DTS 答复可用于理解命令 service 名称大小写、常见示例与用户/系统范围差异；其中某些清单是历史版本数据。实施需本机手册和隔离实测，不能直接硬编码旧名单即宣称兼容新系统。

### [S06] Apple Developer Forums：tccutil reset doesn't remove items from System Default Permissions
来源：`https://developer.apple.com/forums/thread/724635`

这是开发者的一手故障报告，而非普遍行为的官方保证。报告涉及卸载后 bundle ID 无法解析、权限 UI 记录仍残留。本文用它确定必须测试的失败场景，不断言所有系统必然失败。

### [S07] Apple Developer Forums：How to reset/remove apps from Local Network privacy
来源：`https://developer.apple.com/forums/thread/766270`

Apple DTS 解释隐私设置并非全部由 TCC 统一管理；本地网络/定位需要区分。当前重置能力优先参考下方较完整的官方技术说明，不采用论坛中用户尝试修改私有 plist 的办法。

### [S08] Apple Technote TN3179：Understanding local network privacy
来源：`https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy`

用于本地网络的独立作用域、签名身份及重置限制。研究时文档说明 macOS 无法把该权限重置到未确定状态，测试建议使用 VM 快照或新用户。这个事实不等于“系统设置无法切换允许/拒绝”；两种操作需区分。

### [S09] Apple archived guide：Creating Launch Daemons and Agents
来源：`https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html`

历史官方资料用于配置目录层次和基本 launchd 概念。现代 launchctl 命令语义及新登记方式以目标机器的当前手册/API 为准，不从旧文档推导未验证写能力。

### [S10] Apple App Store Review Guidelines，2.4.5
来源：`https://developer.apple.com/app-store/review/guidelines/`

Mac 商店的 sandbox、自包含与权限提升限制影响本工具完整版的分发路线。选择直接签名公证分发是本项目架构决策，不是对所有 macOS 工具上架可行性的泛化判断。

### [S11] Apple Developer：Notarizing macOS software before distribution
来源：`https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution`

用于直接分发的软件签名/公证计划。具体账号、证书、构建命令和服务行为由实际发布环境确认，当前文档不包含任何可用发布凭据。

### [S12] Apple Developer：Xcode SDK and system requirements
来源：`https://developer.apple.com/xcode/system-requirements`

用于宿主 macOS 与 Xcode/SDK 的匹配。文档选择兼容稳定工具链，不把检索缓存中某个 beta 标成必须安装版本。实际编译器和 SDK 由 preflight 与项目 lock 文档记录。

### [S13] OpenAI：AGENTS.md project instructions
来源：`https://developers.openai.com/zh-Hans/docs/agent-configuration/agents-md`

用于 Codex 的项目级约束组织。根 AGENTS 保持精炼，详细规格分文件，任务提示明确要求按顺序读取。不建议在初次开发中禁用确认策略或无限放开系统命令。

## 8.2 设计决策记录

### ADR-001：不是“全权限数据库编辑器”
选择安全可维护的源级工具。理由：来源机制不同，新系统进一步限制直读。结果：现代权限页允许 guidedOnly，产品文案真实说明不足。

### ADR-002：原生 SwiftUI + Swift 核心
选择单平台原生栈，减少桥接和特权 IPC 的复杂度。系统集成关键处用窄 AppKit/平台适配，而不是整个项目退回跨平台 Web UI。

### ADR-003：来源、存在性、操作能力三分离
记录即使红色也可能不能直接清理；仍安装的软件也可能有允许用户删除的启动设置。结果：UI 状态与操作按钮由多个维度共同计算。

### ADR-004：未知项首期不可清理
宁可把证据不足标为待核实，也不以低分阈值换取更多“可清理”条目。结果：不提供跳过未知归属的高级危险按钮。

### ADR-005：按实际影响计算确认次数
行级用户意图和系统动作粒度可能不一致。结果：需要影响展开、不可变计划和确认失效机制，不能在按钮点击处理器中直接删除。

### ADR-006：配置隔离优于永久删除
保留可验证恢复能力。结果：备份、metadata、journal 是清理前置条件，不是后期附加功能；权限重置明确不属于可恢复授权。

### ADR-007：未知系统只读降级
平台变化可使旧解析和操作语义失效。结果：发布需能力 profile，未验证版本不承诺全部功能，也不退出整个工具。

### ADR-008：首期不做背景自动清理
用户选择是需求核心，后台自动清理风险高。结果：应用自己默认不随登录启动，不安装隐藏监控，helper 按需且透明。

### ADR-009：完整版直接签名公证分发
避免把受限商店模型与管理员级工具能力混在一套规格里。未来只读商店版独立评估。

## 8.3 尚待实测的问题
具体 OS/build 下的 BTM 输出/授权范围；旧式登录项可枚举和可写程度；helper peer 身份认证的目标 SDK 实现；已卸载 bundle 的定向 reset 成功率及后置显示；各权限的粒度/作用域；共享 Agent 多用户行为；各类恢复路径。

这些不是当前包已完成的结果。P0/P4/P5 负责逐项建立真实证据，未完成前相关写能力保持关闭。
