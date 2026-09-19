# P2 只读 GUI 接入边界

本次 GUI 将演示夹具与真实来源记录显式区分。`WorkspaceRecord` 保留原始 `SourceRecord`、代次、来源身份、来源文件、解析警告与能力理由。真实行不论存在状态如何均禁止勾选；`makePlan` 只允许已载入合成演示时调用。没有系统写执行入口。

## 目录与沙箱

保持 App Sandbox；新增 `com.apple.security.files.user-selected.read-only`（Xcode `ENABLE_USER_SELECTED_FILES = readonly`）。用户通过 `NSOpenPanel` 选择目录，再另行点击只读扫描。没有启动时扫描，没有自动权限申请，没有书签或持久化授权，没有 helper。

生产 GUI 的启动配置目录只接受当前真实用户的 `Library/LaunchAgents`、`/Library/LaunchAgents`、`/Library/LaunchDaemons`、`/System/Library/LaunchAgents`、`/System/Library/LaunchDaemons`。应用索引目录限 `/Applications`、`/System/Applications` 或当前用户主目录内显式选择的目录。当前用户由 `getpwuid(getuid())` 获取，避免错误使用沙箱容器主目录作为实际用户身份。底层采集器仍独立检查目录与文件，不依赖 UI 验证实现路径安全。

所有 security-scoped access 在本次扫描返回后成对释放。未选应用索引根不代表系统没有应用；来源覆盖保留缺口。主动选择目录的真实 Powerbox 交互验收尚未运行，不计为通过。

## 代次与取消

一次仅运行一个扫描任务。开始扫描清除旧行、选择、检查器与预演计划；不会把旧行混作新结果。扫描时禁止载入演示、修改根目录和再次扫描；取消立即给出反馈，等待采集器收拢部分结果。取消返回的来源状态按 `cancelled` 呈现，不当空清单或扫描成功。

## 测试边界

Debug 构建仅在显式 `--ui-synthetic-scan` 参数下使用注入的合成扫描器。横幅标明“测试注入 · 合成扫描结果，非本机数据”；Release 编译排除该组合分支。`--ui-slow-scan` 只延迟合成扫描以验证取消，不读取主机。新增 UI 测试覆盖来源卡片/真实形状行禁用、演示切换的选择失效、取消与并发按钮限制。测试通过状态以本轮实际测试报告为准，源码存在不等于通过。

真实系统目录选择、沙箱权限拒绝的实际行为，以及人工浅/深色、高对比度、VoiceOver、长路径外观验收仍需单列实际结果。本模块不把合成 UI 测试当作系统集成验证。
