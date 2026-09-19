# P0 / P1 实际验证记录 — 2026-09-20

范围仅环境核验、合成策略、原生只读 GUI 和 dry-run。没有主机清理、系统权限重置、服务卸载或 helper 安装。

## 环境

macOS 27.0 (26A428), arm64；已安装 Xcode 27.0 (27A266a)，Swift 6.4，SDK 27.0；Swift 6 language mode，deployment target 14.0。未测试 macOS 14/15/26 或 Intel。签名、公证、真实源能力与构建结果分开记录。

## 已观察到的前置失败与修正

1. 默认 `bash script/preflight.sh` 读到 Command Line Tools；项目改用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，未修改全局选择。
2. 首次指定 Xcode 预检受未接受许可阻止（SDK 探测 exit 69）；本轮后续预检与 `xcodebuild -checkFirstLaunchStatus` 已成功。代理没有执行接受许可命令，状态变化来源未知。
3. 工程文件尚未生成时提前执行构建/UI 脚本，报缺少 `project.pbxproj`（exit 74）。这是构建准备失败，不是 UI 测试通过；最终工程生成后重新验证。
4. 核心测试首次用 CLT 默认构建时遇到 Swift Testing 宏插件缺失；CLT native 构建也因缺少 Testing 模块失败。完整 Xcode 第一次编译暴露测试中 mutating 宏表达式用法错误，已修正。最终使用完整 Xcode 工具链，失败尝试不计入通过。

## 核心测试：passed

实际命令：`./script/test.sh core`（内部固定 Xcode，执行 `xcrun swift test --package-path Packages/ResidueCore`）。exit 0，**10 个 Swift Testing 测试通过，0 失败**。其中一个测试逐一执行 `fixtures/confirmation-cases.json` 的 24 个 F01–F24 案例；这是 10 个测试中的 24 个数据输入，不把它们重复相加为 34 个测试。XCTest 兼容层输出的 0 tests 不作为测试通过证据，以后续 Swift Testing 的 10 项结果为准。

覆盖：空选/全残留/正常/混合/未知/保护/范围扩大策略；同底层操作影响合并与去重；具体动作能力缺失和禁用；未知 OS build、缺失和重复身份、空指纹、同动作指纹或类型冲突；稳定存在性证据、离线卷、权限不足、Trash、运行反证、CLI 与共享 owner；独立确认事件、风险短语与重放；源指纹变化、过期、未来时间与快照剩余有效期。

源码核心不导入 SwiftUI/AppKit，不启动进程、不读主机系统源、不提供执行器。可序列化 dry-run 对象不是真实写入授权 token；未来执行器必须独立校验来源与签名、影响、备份及授权。

## Xcode 与 UI 测试

`./script/build_and_run.sh --build-only`：最终 exit 0，`BUILD SUCCEEDED`。首次完整工程编译因 Debug 应用请求 x86_64 而核心包仅当前 arm64 架构而失败（exit 65）；已把 Debug `ONLY_ACTIVE_ARCH=YES` 与本地包一致，不据此宣称 Intel 兼容。

`./script/test.sh ui`：exit 0，`TEST SUCCEEDED`。**6 个 XCUITest 通过，0 失败，45.034 秒**，实际启动本项目 `.app` 并操作合成记录：

1. 默认无扫描/无演示；权限页面显示不可完整读取。
2. 详情选中不自动勾选；离线、未知、保护行禁用选择。
3. 同页搜索隐藏选择保留并计数；切换页面清空选择。
4. 全残留范围预览之后一次模拟确认完成。
5. 已安装软件需要独立第二次确认；首次双击和连续回车不越过第二页，输入指定短语后才完成。
6. 红色关系的扩大影响明确列出已安装软件，范围批准不抵扣两次确认，可取消。

本地 Debug 采用 ad-hoc 签名；Xcode 明确提示该模式关闭 hardened runtime。发布签名、公证和 helper 信任没有通过本次测试。UI 测试产物的临时 testmanager 调试 entitlement 不属于普通构建权限承诺；最终正常启动重新构建并单独检查签名与 entitlement。

## 干净构建、启动和签名：passed

实跑 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ResidueGuard.xcodeproj -scheme ResidueGuard -configuration Debug -derivedDataPath .build-xcode clean`，随后 `./script/build_and_run.sh --verify`：组合命令 exit 0，clean/build 成功，`open -n` 启动 `.app`，`pgrep -x ResidueGuard` 找到进程。没有把裸 Swift executable 当 GUI 启动。

`codesign --verify --strict --verbose=2 .build-xcode/Build/Products/Debug/ResidueGuard.app`：exit 0，valid on disk / satisfies Designated Requirement。`codesign -d --entitlements - ...`：普通构建只有 `com.apple.security.app-sandbox=true` 与 `com.apple.security.get-task-allow=true`。这是本地 ad-hoc Debug 校验，不是 Developer ID 或公证。

额外人工窗口/截图检查：`cua.getApp("com.residueguard.app")` 连续两次报 `Sky Computer Use native pipe closed before response`，无法取到窗口状态；此项为 **notRun（工具通道不可用）**，不声称已做像素级外观/浅深色/最小窗口检查。真实 GUI 交互证据来自上述已通过 XCUITest。

## 静态检查：passed

`bash -n script/*.sh`、`plutil -lint ResidueGuard.xcodeproj/project.pbxproj`、JSON 解析与能力矩阵所有 mutation 禁用断言、`git diff --check` 均成功。源码审查未发现系统进程执行器、服务注册、权限重置或删除接口。构建缓存、原始构建日志与 xcresult 留在 git 忽略目录，不提交个人路径或测试截图。

## 系统集成与兼容性

以下全部 `notRun`：真实 LaunchAgents/BTM/登录项采集、TCC 权限枚举或重置、helper 安装/签名握手、多用户作用域、VM 隔离清理与恢复、系统设置历史刷新、Developer ID/公证、跨 OS/Intel 兼容性、VoiceOver/高对比度、10,000 行性能。没有隔离环境的系统行为实验没有在日常主机替代执行。

所有产品系统写能力仍关闭；没有全局 reset 路径、TCC/BTM 数据库访问、通用命令执行器、真实备份/恢复执行器。模拟确认完成只表示 dry-run 策略交互完成，不代表真实清理成功。

## 下一有界任务

先补齐本报告仍未通过的 P1 验收；另行开始 P2 时才实现真实只读来源，并逐来源报告覆盖、错误与 provenance。真实 mutation 必须等隔离测试与后续阶段安全门槛通过，不由 P1 合成测试开放。

## 实际修改文件

以下为本轮相对原始规格提交 `7869b58` 的文件清单（构建缓存和本地证据不纳入源码）：

- `.codex/environments/environment.toml`
- `.gitignore`
- `App/ResidueGuardApp.swift`
- `Features/CleanupReview/CleanupReviewView.swift`
- `Features/Overview/OverviewView.swift`
- `Features/Permissions/PermissionGuidanceView.swift`
- `Features/Records/RecordInspector.swift`
- `Features/Records/RecordsView.swift`
- `Features/Settings/SettingsView.swift`
- `Features/Workspace/WorkspacePage.swift`
- `Features/Workspace/WorkspaceStore.swift`
- `Features/Workspace/WorkspaceView.swift`
- `Packages/ResidueCore/Package.swift`
- `Packages/ResidueCore/README.md`
- `Packages/ResidueCore/Sources/ResidueCore/ConfirmationPolicy.swift`
- `Packages/ResidueCore/Sources/ResidueCore/ConsentSession.swift`
- `Packages/ResidueCore/Sources/ResidueCore/Models.swift`
- `Packages/ResidueCore/Sources/ResidueCore/Planning.swift`
- `Packages/ResidueCore/Sources/ResidueCore/SourceRecord.swift`
- `Packages/ResidueCore/Tests/ResidueCoreTests/PolicyTests.swift`
- `Platform/Demo/DemoRecord.swift`
- `README.md`
- `ResidueGuard.xcodeproj/project.pbxproj`
- `ResidueGuard.xcodeproj/xcshareddata/xcschemes/ResidueGuard.xcscheme`
- `Resources/demo-records.json`
- `Tests/UI/ResidueGuardUITests.swift`
- `docs/validation/capability-matrix.json`
- `docs/validation/environment.md`
- `docs/validation/provider-dossier.md`
- `docs/validation/status.md`
- `docs/validation/test-results-2026-09-20.md`
- `script/build_and_run.sh`
- `script/test.sh`
