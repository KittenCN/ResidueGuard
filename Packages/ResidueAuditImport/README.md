# ResidueAuditImport

NSOpenPanel 显式选择文件之后的只读边界。依赖 ResidueRecovery；该模型包仍不包含文件 I/O。这里不打开选择器、不获取授权、不保存 bookmark、不枚举目录，也不写文件或执行恢复。

公共 API：

```swift
let summary = try SelectedAuditReportReader.readSummary(from: selectedURL)
```

调用方必须维持这次用户选择产生的 security scope，在后台任务调用同步 API，并在返回/失败后释放授权。API 只返回脱敏 RecoveryReviewSummary，不返回完整原始快照。

路径先拒绝 NUL（包括 URL 中的 %00 编码）及达到 PATH_MAX 的 UTF-8 路径；合法文件名文字 %00 编码为 %2500，不混淆。路径用 Darwin `O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC` 打开，不与 `O_NOFOLLOW` 并用。任一级 symlink 被拒绝；打开后要求当前有效用户拥有、单硬链接、普通文件。目录/FIFO 等不读取。先检查大小，随后分块读取最多 `maximumEnvelopeBytes + 1` 字节，保证初始 stat 后文件增长也不会无界读。每块检查 Task cancellation；解码前后也检查取消。

读前后在同一 fd 上复核 dev/inode/size/uid/gid/mode/mtime/ctime，观察到普通并发修改即 `changedDuringRead`。这是稳定读观察，不是锁定源文件；无法证明同 UID 攻击者不能修改并重置元数据。内容校验仍不是真实性/授权证明，summary 始终未经验证、不可自动执行。

错误：AuditImportError 的 inaccessible / unsupportedFile / oversized / changedDuringRead；模型的损坏、未知版本等错误继续由 RecoveryAuditError 表达；取消抛 CancellationError。没有“出错返回空报告”。

验证命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueAuditImport
```

2026-09-20 macOS 27.0/26A428、Xcode 27.0/27A266a：15 个测试通过。全部文件/FIFO/链接/权限故障只在 `/private/tmp/ResidueAuditImportTests-*` 自有随机目录。资源 `Fixtures/valid-audit.json` 是纯合成审计 envelope，不含用户数据或授权；其 placeholder plan digest 不作为真实性证明。

App 集成建议（本次没有修改 App/工程）：

1. App target 添加本地 package/product ResidueAuditImport。
2. HistoryReportStore 导入该模块；保留现有 NSOpenPanel 和 Task 生命周期。
3. 原 `readReport` 只保留 `startAccessingSecurityScopedResource` / defer stop，内部调用 `SelectedAuditReportReader.readSummary(from:)`，删除重复 fd 读取代码。
4. 用 AuditImportError 替换私有 HistoryImportError 的对应消息；changedDuringRead 显示“文件在读取期间发生变化，请重新选择报告”，不能当空历史。
5. 继续执行现有 4 个稳定 UI 测试；真实 picker 系统授权仍由显式环境集成/CUA 另行验收，本包测试不代替它。
