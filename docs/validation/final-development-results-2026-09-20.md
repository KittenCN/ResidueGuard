# 后续开发综合结果 — 2026-09-20

本轮按用户继续全项目开发的授权扩展实现；没有把开发授权解释为清理日常主机的许可。全项目仍未完成：受限只读扫描、策略、引导和报告可开发验证，真实清理/helper/分发需要尚未具备的生产实现与隔离证据。`notRun` 不计 passed。

## 环境与安全边界

macOS 27.0 / 26A428，arm64；Xcode 27.0 / 27A266a，Swift 6.4，SDK 27，Swift 6 language mode。工程最低部署目标 14.0 不代表已测试 macOS 14/15/26 或 Intel。固定 `DEVELOPER_DIR`，未升级系统、安装工具、接受许可或安装 helper。

GUI 继续沙箱运行；用户目录选择与启动只读扫描分开；请求用户所选目录的只读访问，不持久化授权。没有源配置删除、launchd bootout、权限重置、全局 reset、TCC/BTM 数据库访问或应用文件删除。诊断 runner 的超时/取消只结束其自己创建的诊断子进程，不是停止被扫描服务。

## 实际实现与文件范围

- `Packages/ResiduePlatform`：有界 no-follow 文件读取、plist 解析与失败行保留、应用多实例索引、来源覆盖与取消、固定只读诊断子进程、静态签名元数据和 `ResidueProbe`。相关 GUI 范围为 `Features/Workspace`、`Features/Records`、`Features/Overview`、`Platform`、工程 entitlement/包依赖与 `Tests/UI`。
- `Packages/ResidueCore`：快照比较；`TransactionModels.swift`、`TransactionCoordinator.swift`、`RecoveryPolicy.swift` 的合成事务/恢复边界；`PermissionCatalog.swift` 的 19 类权限机制；`AuditReport.swift` 的默认脱敏 JSON/CSV，与对应测试。
- `Packages/ResidueSecurity`：有限协议 DTO、默认拒绝身份适配器、精确调用者策略、server plan 与 token/nonce/期限/连接绑定，以及 9 项测试。没有 helper 可执行文件、安装器或真实 XPC 传输。
- `Features/Permissions/PermissionGuidanceView.swift` 与 `Features/Overview/OverviewView.swift`：权限注册表引导、脱敏报告预览；`script/test.sh` 扩展包测试入口；`script/package_preview.sh` 与 `script/release_check.sh` 提供本地预览打包及只读分发门禁。
- 文档更新包括 P2 实测、事务安全准备、权限支持、发布准备、`docs/user-guide.md` 用户指南、隔离要求和本报告/阶段状态。准确逐文件提交差异可由本轮 Git 提交及未提交 diff 核对；这里按模块列出，不包含构建缓存、原始私有记录或日志。

关键阶段已保存提交：`80b2b2b`（受限只读扫描/目录授权）、`1a50412`（事务/helper 纯策略）。后续提交记录以 Git 为准；不因代码已提交推断平台验收完成。

## 已运行的验证

| 命令/检查 | 真实结果 | 能证明的范围 |
|---|---|---|
| `./script/test.sh core` | passed，30 项 | 24 条确认 fixture（在一项测试内）、计划/确认/分类/比较、10 项事务恢复测试、权限与报告策略 |
| `./script/test.sh security` | passed，9 项 | 默认拒绝、精确身份策略、版本/scope、过期、篡改、重放、连接/server plan 变化；不是 XPC OS 集成 |
| `./script/test.sh platform` | passed，21 项 | 解析/读取限额/取消/路径边界、固定诊断子进程、静态签名 metadata 边界；不证明完整签名信任 |
| 10,000 条合成报告生成 | passed，观测 0.437242541 秒（JSON + CSV 合计） | 核心报告生成/脱敏，不是 GUI 滚动、扫描吞吐或可访问性测试 |
| `./script/test.sh ui`（最终总计 11 项） | passed，11 项，0 失败，94.763 秒，exit 0 | 完整 GUI 回归；另有报告预览 targeted 1 项修复复测，不重复相加计数 |
| `./script/package_preview.sh` | passed，exit 0；BUILD SUCCEEDED，严格 codesign 校验通过 | 仅本地 Debug 预览 ZIP，非正式发布 |
| `./script/release_check.sh` | failed（预期拒绝当前预览包），exit 2 | 缺少 Developer ID、Hardened Runtime，且 get-task-allow=true；正式分发未通过 |
| `./script/build_and_run.sh --verify` | passed，exit 0 | 正常 `.app` 启动及进程验证；不是裸 Swift executable |

以上为最终实跑结果。发布检查发现并拒绝不满足分发条件的预览包；门禁正常拒绝不能把正式分发结果改计为 passed。

GUI 报告预览回归保留两次先前失败：首先报告按钮尚未正确提供而断言失败，补齐按钮后又出现正文读取断言失败。第二次原因：可选择 Text 的 `.label` 未包含正文；为正文设置显式 `accessibilityValue` 并对 `.value` 断言后，针对性 1 项测试通过。没有删除内容核验或放宽预期文字。此后完整 11 项回归已单独通过（94.763 秒，0 失败）。核心报告测试增加 CSV 来源列后复跑 30 项通过；旧观测 0.244 秒只包含 JSON，当前 0.437242541 秒包含 JSON + CSV，不能直接视为性能退化。Settings 也已移除过时 P1 / 未启用扫描的文案。

## P2 真实只读观测与限制

已实跑 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path Packages/ResiduePlatform ResidueProbe --host-readonly`；早期本轮记录为 14 条配置（含 2 条失败来源行）、43 个应用实例、0 高可信残留。只输出脱敏计数，逐根覆盖详见 [P2 记录](p2-results-2026-09-20.md)。这是当时声明目录内的样本，不是全系统登记清单，也不保证之后文件未变。

只读 collector 已补齐 aggregate budget、原始预览限量、失败行 provenance、取消和未授权卷未知状态。签名只读探针对最多 32 个实例尝试读取：25 个返回 metadata、7 个 unavailable，另有 11 个未尝试而 unverified。签名新增能力只读取静态代码元数据；未执行 trust validity 验证，不能据此断言开发者可信或归属完整。runtime/BTM/登录项 profile、完整应用位置覆盖、共享 owner 图仍缺失；真实行无清理选择，未将缺失文件直接标为可清理高可信残留。

真实 NSOpenPanel 授权/拒绝及 sandbox 扩展的完整人工端到端验收仍 notRun；UI 注入合成扫描不替代该验收。

## P3/P4 的实际边界

事务生产 gate 默认关闭，没有 production-enabled 配置；协调器只接受 currentUser + synthetic profile。Fake driver 测试证明调用顺序/失败停止/备份与日志前置/重放处理，不证明磁盘满、TOCTOU、真实 bootout 或崩溃恢复已通过 OS 验证。恢复只生成配置恢复计划，不恢复旧权限，不自动启动服务。

helper 包成功结果为 review-only validation；默认认证不可用。没有生产 driver、真实持久化备份/隔离/journal、系统授权、helper 安装/签名握手、root 文件操作或持久执行 token。详见 [事务和安全准备](transaction-security-preparation.md)。这些是尚未实现的能力，不只是在等待用户开启的现成清理开关。

## P5/P6 的实际边界

19 类权限保留机制区别；macOS 27+ 不直读 TCC，未知或未经测试的 reset 保持禁用。完整权限枚举、旧版可选 adapter、真实 caller-target reset 和后置 UI 历史验证没有运行。

报告默认脱敏，不提供直接执行导入。10,000 条核心处理测量不能冒充 GUI 性能。预览包即使生成也只是 ad-hoc Debug 构建；正式发布需要 Developer ID、Hardened Runtime、公证、干净安装/升级/自身 helper 撤销验证。窄范围 VM 工具盘点未发现常见工具，可用代码签名 identity 计数为 0；范围限制见 [隔离验证](../isolated-validation.md)。

## 未验证能力与下一步

以下均未通过本轮验收：可回滚 VM 自有服务清理与恢复、P4 签名 XPC 攻击矩阵、多用户/shared/system 操作、真实权限修改及历史刷新、跨 OS/Intel、VoiceOver/高对比度/完整人工外观、正式签名/公证/发布/卸载。不能将 `notRun` 汇总进通过数量。

新增 UI 回归与报告预览交互已通过；下一步补齐真实目录授权验证；继续 P2 可审计只读 profile。具备隔离环境与合适签名之后，另行实现生产 driver/helper 并完成 M/S 测试矩阵，再逐项开放经验证能力。当前所有真实 mutation 保持关闭。

## 本地预览产物与发布检查

`dist/ResidueGuard-development-preview.zip` 及 `dist/preview-manifest.json` 仅留本地忽略目录。ZIP 的 SHA256：`af15144bbf8ac994d9225c377f22a16824c1c75e63798e329664a7e9d97500d2`。另运行只读 ZIP 校验：`zipfile.testzip()` 返回 `None`，包含 `.app/Contents/MacOS/ResidueGuard`，manifest SHA256 与 ZIP 实算一致，exit 0。产物通过普通本地严格签名校验，但属于 ad-hoc Debug，未公证，不是正式分发包。

普通 bundle 的 entitlement 仅有 `com.apple.security.app-sandbox`、`com.apple.security.files.user-selected.read-only`、`com.apple.security.get-task-allow`；未发现 temporary exception。发布脚本因非 Developer ID、无 Hardened Runtime 与调试 entitlement 三项拒绝，未进入后续可通过声明。没有上传/安装/公证行为。

## 完整修改文件索引

以下按本轮相对 P0/P1 完成提交 `944833c` 的已跟踪差异，加当前新文件生成；所有路径均为仓库相对路径。删除了过时的 `PACKAGE_VALIDATION.md` 与 `SHA256SUMS.txt`，原版可在 Git 历史查询。构建缓存、原始日志、xcresult、个人软件清单与 dist 产物不计入源码清单。

### GUI 与工程

- `Features/Overview/OverviewView.swift`
- `Features/Permissions/PermissionGuidanceView.swift`
- `Features/Records/RecordInspector.swift`
- `Features/Records/RecordsView.swift`
- `Features/Records/WorkspaceRecord.swift`
- `Features/Scanning/ScanAccess.swift`
- `Features/Scanning/ScanControlsView.swift`
- `Features/Scanning/ScannerComposition.swift`
- `Features/Settings/SettingsView.swift`
- `Features/Workspace/WorkspaceStore.swift`
- `Features/Workspace/WorkspaceView.swift`
- `Platform/Demo/DemoRecord.swift`
- `ResidueGuard.xcodeproj/project.pbxproj`
- `Tests/UI/ResidueGuardUITests.swift`

### 核心、平台与安全包

- `Packages/ResidueCore/README.md`
- `Packages/ResidueCore/Sources/ResidueCore/AuditReport.swift`
- `Packages/ResidueCore/Sources/ResidueCore/PermissionCatalog.swift`
- `Packages/ResidueCore/Sources/ResidueCore/RecoveryPolicy.swift`
- `Packages/ResidueCore/Sources/ResidueCore/SnapshotComparison.swift`
- `Packages/ResidueCore/Sources/ResidueCore/TransactionCoordinator.swift`
- `Packages/ResidueCore/Sources/ResidueCore/TransactionModels.swift`
- `Packages/ResidueCore/Tests/ResidueCoreTests/PermissionCatalogTests.swift`
- `Packages/ResidueCore/Tests/ResidueCoreTests/ReportTests.swift`
- `Packages/ResidueCore/Tests/ResidueCoreTests/SnapshotComparisonTests.swift`
- `Packages/ResidueCore/Tests/ResidueCoreTests/TransactionTests.swift`
- `Packages/ResiduePlatform/Package.swift`
- `Packages/ResiduePlatform/README.md`
- `Packages/ResiduePlatform/Sources/ResiduePlatform/CodeIdentityInspector.swift`
- `Packages/ResiduePlatform/Sources/ResiduePlatform/Diagnostics.swift`
- `Packages/ResiduePlatform/Sources/ResiduePlatform/LaunchConfigurationParser.swift`
- `Packages/ResiduePlatform/Sources/ResiduePlatform/SafeFiles.swift`
- `Packages/ResiduePlatform/Sources/ResiduePlatform/ScanModels.swift`
- `Packages/ResiduePlatform/Sources/ResiduePlatform/ScanService.swift`
- `Packages/ResiduePlatform/Sources/ResidueProbe/main.swift`
- `Packages/ResiduePlatform/Tests/ResiduePlatformTests/CodeIdentityTests.swift`
- `Packages/ResiduePlatform/Tests/ResiduePlatformTests/CollectorTests.swift`
- `Packages/ResiduePlatform/Tests/ResiduePlatformTests/DiagnosticTests.swift`
- `Packages/ResidueSecurity/Package.swift`
- `Packages/ResidueSecurity/README.md`
- `Packages/ResidueSecurity/Sources/ResidueSecurity/Contracts.swift`
- `Packages/ResidueSecurity/Sources/ResidueSecurity/HelperPolicy.swift`
- `Packages/ResidueSecurity/Tests/ResidueSecurityTests/HelperPolicyTests.swift`

### 脚本

- `script/package_preview.sh`
- `script/release_check.sh`
- `script/test.sh`

### 文档与根文件

- `PACKAGE_VALIDATION.md`
- `README.md`
- `SHA256SUMS.txt`
- `docs/isolated-validation.md`
- `docs/permission-support.md`
- `docs/release-readiness.md`
- `docs/user-guide.md`
- `docs/validation/capability-matrix.json`
- `docs/validation/final-development-results-2026-09-20.md`
- `docs/validation/p2-gui-boundary.md`
- `docs/validation/p2-results-2026-09-20.md`
- `docs/validation/project-progress.md`
- `docs/validation/status.md`
- `docs/validation/transaction-security-preparation.md`
