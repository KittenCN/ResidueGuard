# 02｜开发环境、架构与数据契约

## 2.1 技术选型
| 层次 | 选择 | 取舍 |
|---|---|---|
| 工程 | 原生 Xcode macOS App + 本地 Swift Package | 主应用、签名、辅助程序与 UI 测试在 Xcode；核心逻辑独立测试 |
| 语言 | Swift 6 language mode | 明确并发边界，尽早处理 Sendable/actor 隔离 |
| UI | SwiftUI，必要处窄范围 AppKit | 原生表格、侧栏、菜单、键盘、检查器和设置窗口 |
| 系统交互 | Foundation / Security / ServiceManagement / XPC | 公开 API 优先；诊断 CLI 独立适配层 |
| 本地存储 | SQLite，仅保存本应用索引、计划日志和历史 | 用小型封装、显式 migration；与系统权限数据库完全分离 |
| 测试 | Swift Testing 核心测试；XCTest/XCUITest 集成和 UI | 无需真实系统副作用即可覆盖大多数策略 |
| 分发 | Developer ID 签名、Hardened Runtime、公证、DMG | 首期不以 Mac App Store 为目标 [S10][S11] |
| 运行模式 | 普通 GUI + 按需安装的自身特权 helper | GUI 不提权；不为普通扫描自动装 helper |

建议以实际主机可运行的稳定 Xcode 为主，不盲目安装最新测试版。记录精确版本和构建号，而不是将本文件中的“稳定版”当永久版本锁。Xcode 与宿主 macOS 的兼容性以官方表及本机工具结果核验 [S12]。

不选 Electron/Tauri/Python 作为主要 GUI 的原因是：本项目只有 macOS 目标，系统集成和最小权限是核心，额外运行时和跨语言特权桥接增加安全审计面。不是这些框架做不到界面，而是本项目没有对应收益。

## 2.2 建议目录
```text
ResidueGuard/
├── AGENTS.md
├── README.md
├── ResidueGuard.xcodeproj/             # P1 真实创建
├── App/                              # @main / AppDelegate / composition root
├── Features/
│   ├── Overview/
│   ├── LoginItems/
│   ├── BackgroundItems/
│   ├── LaunchServices/
│   ├── Permissions/
│   ├── Applications/
│   ├── CleanupReview/
│   ├── History/
│   └── Settings/
├── Packages/ResidueCore/
│   ├── Package.swift
│   ├── Sources/ResidueCore/
│   │   ├── Models/
│   │   ├── Identity/
│   │   ├── Policies/
│   │   ├── Planning/
│   │   └── Reporting/
│   └── Tests/ResidueCoreTests/
├── Platform/
│   ├── Collectors/
│   ├── ApplicationIndex/
│   ├── Launchd/
│   ├── BackgroundTaskManagement/
│   ├── Permissions/
│   ├── FileSystem/
│   ├── ProcessExecution/
│   ├── Persistence/
│   ├── SystemSettings/
│   └── XPC/
├── Helper/                           # 自身 on-demand 特权执行器
├── SharedContracts/                  # 版本化 IPC DTO，不共享任意命令接口
├── Resources/                        # 本地化、能力策略、资源
├── Tests/{Integration,UI,Fixtures}/
├── docs/
├── script/
└── .codex/environments/              # 真实构建入口完成后再配置 Run
```

当前任务包只包含文档、模板和只读脚本。上述工程树是目标结构，不应误认为已经存在的应用。

## 2.3 模块依赖规则
`Features → AppServices → Core protocols`；`Platform` 实现 Core 定义的边界；`Helper` 只依赖 SharedContracts、被审核的策略子集和安全执行代码。Core 不导入 SwiftUI/AppKit，不直接启动 Process，不读写系统文件。

应用组装根显式注入 `FileSystemClient`、`ProcessRunner`、`Clock`、`CapabilityRegistry`、`RecordProviders`、`AuthorizationClient`、`BackupStore`、`JournalStore`。测试替换实现，不靠全局 singleton 改状态。

扫描器只读；分类器是可重放纯逻辑；计划器不执行；执行器不重新猜测 UI 勾选意图。禁止写出一个同时扫描、判断、删除、弹窗的 `CleanerManager`。

## 2.4 关键模型
以下为接口规格，不是声称可直接编译的 SDK 示例；具体声明由 P1 按本机 Swift 版本实现。

### SourceRecord
字段：
`id: RecordID`、`providerID`、`category`、`scope`、`nativeIdentity`、`observedAt`、`generation`、`sourceArtifact`、`displayName`、`declaredAppIDs`、`targetReferences`、`rawMetadata`、`parseWarnings`。

`RecordID` 由 provider、作用域和原生身份形成，不能由软件名或当前表格索引形成。对于没有稳定原生 ID 的源，用版本化规范化数据构造 ID，同时保留组成字段并检测冲突。

TCC 类记录的身份至少区分数据库作用域、service、client、client_type、间接目标；不能只使用 bundle ID，也不依赖跨扫描不稳定的 SQLite rowid。BTM 报告中的源 UUID 在可用时保留，但不能假定跨系统重建永久稳定。

### ApplicationIdentity
字段：`bundleID?`、`teamID?`、`designatedRequirement?`、`signingStatus`、`installationInstances[]`、`executableIdentities[]`。

每个安装实例保留真实 URL、卷身份、文件资源身份、代码签名证据、发现来源和时间。未知 Team ID 明确为未知；不把 nil 和另一个 nil 视为“同开发者”。无 bundle 的合法 CLI 也是软件实体。

### OwnershipGraph
节点为 AppInstance / Executable / Helper / SourceRecord / PermissionRelationship；边包含 declaredBy、embeddedIn、launches、associatedWith、controls 等语义与证据等级。

允许一个组件属于多款软件，同一软件有多个安装副本。模糊名称匹配只能产生弱提示，不能建立决定清理的强归属。

### PresenceVerdict
```text
present
highConfidenceOrphan(evidenceIDs)
suspectedOrphan(missingEvidence)
unknown(reason)
volumeUnavailable(volumeIdentity)
inTrash(instance)
sharedComponentActive(ownerIDs)
protected(reason)
managed(policyEvidence)
```

存在性、保护性与操作能力实现上宜拆开：一条记录可以“高可信残留 + 系统设置才能处理”，也可以“应用已安装 + 被管理”。UI 聚合显示不能抹去多个维度。

### ScanCoverage
`providerID`、`declaredRoots`、`userScopes`、`osBuild`、`startedAt`、`completedAt?`、`parsedCount`、`unparsedCount`、`skippedAreas`、`errors[]`。

状态：`completeWithinDeclaredScope / partial / permissionDenied / unsupported / failed / cancelled`。禁止 `completeSystemInventory = true` 这种无来源依据的全局保证。

### CapabilityDescriptor
分别记录 enumerate/readStatus/removeRegistration/resetPermission/verifyOutcome/restoreConfiguration；每项有 supportState、reason、requiredAuthorization、testedOSBuilds、providerVersion、evidenceReference、scopeConstraints。

能力状态：supportedVerified、readOnly、guidedOnly、unverified、unsupported、blockedByPolicy。未知能力默认不可写。版本上限只是防线之一，还要检查实际输出模式和源类型。

### CleanupPlan
`planID`、`policyVersion`、`snapshotGeneration`、`createdAt`、`expiresAt`、`selectedRecordIDs`、`operations[]`、`expandedAffectedIdentities`、`expectedFingerprints`、`requiredConfirmationCount`、`irreversibleEffects`、`requiredPrivileges`、`planDigest`。

操作类别限白名单：quarantineLaunchConfiguration、bootoutExactService、resetVerifiedPermissionScope、restoreKnownBackup 等。组合成有依赖的步骤，不用通用 shell 字符串。

### ActionOutcome
分别保存 `fileEffect`、`runtimeEffect`、`registrationEffect`、`permissionEffect`。总体状态：succeeded、failed、skipped、partial、pendingSystemRefresh、unverified、guidedOnly。保留错误分类、已执行步骤、补偿结果，不让一个总布尔值遮盖真实状态。

## 2.5 建议接口
```text
RecordProvider.collect(context) async -> ProviderResult
ApplicationInventory.index(scope) async -> InventorySnapshot
OwnershipResolver.resolve(records, inventory) -> OwnershipGraph
OrphanClassifier.classify(graph, coverage, evidence) -> [RecordAssessment]
CapabilityRegistry.resolve(record, environment) -> CapabilityDescriptor
CleanupPlanner.makePlan(selection, snapshot, capabilities) -> PlanResult
ConfirmationPolicy.requiredCount(plan) -> blocked | one | two
CleanupCoordinator.execute(plan, consentReceipt) async -> ExecutionReport
RecoveryPlanner.makePlan(historyEntry, currentState) -> RecoveryPlan
```

所有可变系统观察通过依赖接口完成。一次运行保存分类输入的可脱敏快照，以便重放误判测试。计划中的指纹必须由执行侧重新取值验证，不信任 UI 提供的“verified=true”。

## 2.6 并发与取消
UI Store 在 MainActor；ScanCoordinator、CleanupCoordinator、JournalStore 用独立 actor 管理互斥与代次。文件读、签名验证、子进程读取离开主线程。扫描并发数量可配置并设上限，默认建议 4 个来源任务、签名验证 2 个任务，P1 用性能测试调整。

取消扫描得到 partial/cancelled 快照，不把未访问目录当空。清理同一时刻只允许一个计划执行；扫描可读但其新结果不能更换正在执行的不可变计划。发生身份变化时执行器停止相关操作并使后续依赖失效。

UI 每批次合并变更，避免每读取一行刷新整张表。图标、签名、大小等辅助数据延迟加载，不阻塞主体记录显示。

## 2.7 ProcessRunner
使用固定绝对路径和数组参数。禁止 `/bin/sh -c`、字符串拼接命令、用户提供 executable、从记录中的 Program 路径执行检测。

同时有界读取 stdout/stderr，避免 pipe 满造成死锁；设置 timeout、取消、最大输出与诊断。截断必须显式 `outputTruncated=true` 并影响覆盖状态，不能仍声称完整。必要时将完整输出流写入受限临时文件供解析，限制大小、生命周期和隐私访问。

诊断输出解析器以 fixture 和版本维护；locale 固定只适用于已验证工具，不假定所有工具遵守。命令返回码、信号、stderr 和解析错误分别保留。服务执行命令只在已验证 capability 中开放。

## 2.8 本应用持久化
建议表：scan_sessions、provider_coverage、source_records、identity_instances、ownership_edges、assessments、cleanup_plans、operation_journal、backups、ignore_rules、schema_migrations。

只保存完成任务所必需的元数据；默认不持久化全部原始权限数据库内容。变更日志写入必须先于实际修改；关键状态事务性提交。SQLite 存储失败就禁止开始清理，不在“没有日志”的情况下继续操作。

本用户数据位于本应用 Application Support 下，目录权限限制为本用户；特权备份位于 helper 控制的 root-owned 区域。不要将可恢复的 root 配置写到任意用户指定文件夹。导出报告是单独受用户控制的副本，不是可信恢复源。

## 2.9 错误类型
至少区分 permissionDenied、notFound、volumeOffline、unsupportedOS、unsupportedSource、schemaChanged、ambiguousIdentity、protectedTarget、managedTarget、stalePlan、authorizationCancelled、backupFailed、fingerprintMismatch、commandTimedOut、verificationUnavailable、partialMutation、recoveryConflict。

错误消息包含下一步，但不泄露无关用户数据。任何 `catch { return [] }` 吞掉来源失败的实现都不通过代码审查。
