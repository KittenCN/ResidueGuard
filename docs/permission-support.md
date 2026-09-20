# 权限支持与影响范围策略

本页描述已实现的纯策略及手动引导；不是系统权限能力验收。当前没有权限数据库适配器、tccutil reset 执行器或权限请求代码。

## 分类注册表

`PermissionCatalog` 是 Core 中唯一的权限分类元数据源，GUI 按该表显示说明。包含辅助功能、完全磁盘访问、屏幕与系统音频录制、输入监控、摄像头、麦克风、自动化、文件与文件夹、通讯录、日历、提醒事项、照片、蓝牙、语音识别、开发者工具、本地网络、定位、通知、其他与未知，共 19 类。

注册表区分隐私框架、本地网络、定位服务、通知、未知机制；自动化保留调用者与目标关系，文件/照片/通讯录保留资源子集语义。分类名称不等于 TCC service token：所有 `resetServiceToken` 均为空，不猜测字符串或发现私有符号。

手动路线以 [Apple 的隐私与安全性设置说明](https://support.apple.com/zh-cn/guide/mac-help/-mchl211c911f/mac) 为参考，名称随 OS 可能变化，尚未逐页人工验收。本地网络独立机制参考 [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)。定位路线用“定位服务”；通知位于系统设置的通知页；未知类别仅引导查找并保留记录，不伪造“其他与未知权限”设置页。

## 能力门控

现代分类均为手动引导。完整清单返回 unsupported 或 blockedByPolicy，不显示为零条成功；精确重置始终 blockedByPolicy。macOS 27+ 的旧数据库读取路线 blockedByPolicy；未知系统/build 也阻断。受识别的旧版本仅可能返回 unverified，本项目未启用旧版适配器。

调用方标记 `recognizedEnvironment` 只改变解释文案和只读能力状态，永远不能开启写能力；GUI 当前传 false，因为没有经过验证的权限来源 profile。

## 历史观察与影响集合

`PermissionObservation` 明确保留 origin、时间、调用者和可选目标。`importedHistorical` 永远不是当前授权；观察记录（包括 live）本身永远不授权修改。此处仅提供模型与策略，没有新增历史数据导入 UI 或持久化接口。

`PermissionImpactPolicy` 是供未来计划器使用的纯预检：

- 全量重置一律阻断。
- 历史输入、空选择、空身份、未知实际影响、选择不在实际影响集合内均阻断。
- 声明“逐项”但实际集合更宽时阻断。
- 调用者级操作影响更多关系时，返回完整集合要求重新批准；批准必须与完整实际集合完全相等。
- 影响改变令旧批准失效；`reviewable` 仅表示可以进入后续能力与确认检查，不是执行许可，不绕过一次/两次确认、身份复核与 capability 验证。

纯测试覆盖上述边界和 19 类 × 8 个版本 × 2 种环境识别状态。它们不能验证任何真实系统枚举、授权重置或系统设置列表变化；这些仍为 notRun，必须在隔离环境另行验收。
