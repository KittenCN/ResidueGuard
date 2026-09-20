# 历史审计报告只读导入（2026-09-20）

## 已实现

`Features/History/HistoryReportStore.swift`、`HistoryReportView.swift` 接入 ResidueRecovery；Xcode App target 加入本地包，Workspace 的历史页替换占位页，忽略规则页保持原有独立提示。

用户必须点“导入历史审计报告…”并在 NSOpenPanel 选择单个 JSON 文件。选择器以异步 sheet 附着当前窗口，不自动读取任何目录，不持久保存 URL/bookmark。后台任务读取当前用户拥有、单硬链接、普通文件；使用 `O_NOFOLLOW_ANY | O_NONBLOCK`（不与 O_NOFOLLOW 并用）拒绝路径任意级符号链接，打开后通过 fstat 检查类型/owner/大小。FileHandle 以有界分块读取，最多模型上限加 1 字节；系统拒绝、过大、未知版本、损坏分别显示明确失败，不显示为空历史。

解析和哈希校验在 detached task 中；取消发出任务取消并使 generation 失效，晚到结果不会显示。安全作用域仅在读取期间开启并释放。解析后只将脱敏 summary 留在界面，不保存完整报告内容。所有来源标记未经验证，内容 hash 不代表真实性/授权，备份需要另行核验；界面没有执行、重试或恢复按钮。页面明确不是完整真实清理历史。

Debug-only `--ui-history-fixture` 仅生成内存合成记录，可配 `--ui-history-invalid` / `--ui-history-slow` 验证失败/取消；有明确“合成历史报告，非真实操作记录”标识，Release 不包含此测试入口。

## 实际构建与验证

环境 macOS 27.0（26A428）、Xcode 27.0（27A266a）、Apple Silicon。所有本轮 Xcode 构建成功。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ResidueGuard.xcodeproj -scheme ResidueGuard \
  -destination 'platform=macOS' -derivedDataPath .build-xcode \
  CODE_SIGN_IDENTITY=- '-only-testing:ResidueGuardUITests/HistoryReportUITests' test
```

第二轮实际结果：5 项中 4 项通过、1 项失败。通过的四项：默认未导入与选择取消、合成报告分域结果/未决步骤/脱敏及移除、损坏明确为错误、取消后台导入不呈现结果。失败项为真实系统 picker 自动输入路径：测试没有完成文件选择，不能声称 OS 授权+实际 FileHandle 导入 e2e 通过。

初次测试另外暴露四项断言读取 SwiftUI StaticText 的 label 而非实际 value，以及 UI runner sandbox 无权写 `/private/tmp`。断言改为 value fallback；真实夹具使用 runner 自有临时目录并经 Darwin realpath 获得无符号链接路径，不放宽 App 沙盒或读取边界。

随后把 App picker 从 runModal 改为异步 sheet并定向构建测试，仍无法通过系统 picker 输入：主 App AX 显示 disabled，系统 `com.apple.appkit.xpc.openAndSavePanelService` 在当前 XCTest 桌面会话不可枚举；主 App 键盘事件伴随 DisplayManager 非有限坐标日志并导致选择取消。尝试直接针对该已存在 picker service，仍只有空 Application 查询。相关失败均保留，不属于报告解码通过或读取拒绝测试。

真实 picker 用例现在是显式环境集成测试：需在 **test runner** 环境设置 `RESIDUEGUARD_PICKER_UI_INTEGRATION=1`，并提供可访问系统文件选择器的桌面会话；默认明确 XCTSkip，不能据默认测试成功宣称 picker e2e 已通过。该开关不进入 App，也不放宽生产权限。后续完整 `./script/test.sh ui` 已复测：16 项中 15 通过、1 显式跳过、0 失败（143.409 秒）；历史四项含异步 sheet 取消均通过。

本地证据（不提交）为 `.local-evidence/ui-history-import.log`、`ui-history-import-retest.log`、`ui-history-picker-sheet.log`、`ui-history-picker-service.log`；截图保留在 `history-ui-failure/`。另提供 `.local-evidence/history-picker-fixture.json`（0600，纯合成、不含用户数据），供当前可操作桌面通过 CUA 进行真实选择器验收。

## 未完成边界

当前实现是用户导入文件后的只读核查，不是自动记录全部真实清理历史；SQLite journal 与审计 envelope 的原子绑定尚未接入。本报告提交时，真实文件选择器导入端到端尚未验证。没有服务卸载、文件清理、权限重置、helper 安装或恢复行为。

## 文件读取层后续强化

实际文件读取已抽取至独立 ResidueAuditImport；App 只管理 NSOpenPanel 授权与异步 UI 状态。reader 对读取前后 fd 身份、大小、owner/mode、mtime/ctime再次比较，普通并发变化明确拒绝；这不是报告来源真实性证明。使用包内真实文件测试补足 UI 合成注入不经过文件读取的边界。实际验证：`./script/test.sh audit-import` 15项通过；重新构建成功；读取模块接入后的 History UI 针对性复测为4通过、1显式跳过、0失败（25.068秒）。

主任务尝试真实 CUA picker 验收时，宿主锁屏；用户随后确认已解锁，但 native pipe 连续中断，重置工具会话也未恢复。此环境问题只阻塞手动式 UI 验收，不计为通过，也未停止其余代码测试。
