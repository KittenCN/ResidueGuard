# 保留/忽略配置私有存储（2026-09-20）

新增 `Packages/ResiduePreferences`，只存有界 opaque Data，未修改 Core/App/Xcode。固定 app-owned `ResidueGuard/retention.json`，提供 RetentionPreferenceStore 的 read / save 与 data/revision snapshot。父目录由 App 提供且已存在；未配置 read 返回 nil、不创建目录。保存使用有界 envelope、私有权限、nofollow 全链、目录 fd、合作实例锁、revision 比较和同目录原子替换。

这不是通用文件工具或特权信任根；没有任意文件名、路径清理、规则执行或删除 API。hash 仅检测内容变化，不是授权或真实性证明。锁等待最多 2 秒；rename 后故障与取消返回 writeOutcomeUnknown，必须重新读取，不自动重试。

## 实际验证

环境 macOS 27.0（26A428）、Xcode 27.0（27A266a）、Apple Silicon，Swift 6。执行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePreferences
```

最终 **18 个测试通过，2.015 秒**，无失败/跳过。参数化用例分别包含叶链接 2 项、不安全 mode 4 项、提交后失败 2 项。测试仅操作自有随机临时目录；没有真实用户配置或软件路径数据。

验证首次保存/重开/更新与权限；读未配置不创建；旧 revision/nil 覆盖拒绝；双 store 并发仅一方成功；祖先与叶 symlink、hardlink、父/子目录及文件 mode、ACL 拒绝；数据与 envelope 独立大小上限、128 KiB 全 0xff binary round-trip；损坏/未知版本不是 defaults；取消与 2 秒锁超时；rename 前取消保留旧值；rename 后取消或同步检查点失败明确 unknown，重读可见新值且旧 revision 再提交冲突；目录/锁被替换不能重定向写入。

开发中首次编译暴露 Swift 独占访问约束，已把读缓冲长度移到 mutable borrow 之前。首轮测试的最大 payload 用例失败：JSONEncoder 默认转义 base64 斜线，使全 0xff 的 128 KiB 外包翻倍超限；采用 canonical withoutEscapingSlashes 后最大数据正常通过。没有放宽数据或外包上限。

提交前/后异常通过内部、非公共 API 的确定性检查点测试，实际写入/rename/fsync/读取仍走真实文件系统。并发测试使用两个实例和真实 flock，没有声称验证两个独立进程；锁是合作式约束，不防同 UID 恶意进程完全控制目录，也没有断电测试。

集成接口与错误语义见包 README。上层需要后台调用、明确处理 conflict / corrupt / unsafeStorage / busy / writeOutcomeUnknown；最后一种须开启新的读取任务确认状态，不自动重试。配置不改变源清理确认、安全 gate 或备份验证。

## Fresh sandbox Application Support bootstrap

Added fixed-child bootstrap APIs and switched RetentionStore's background workers
to use the system-provided Application Support URL's Library parent. Existing
worker cancellation forwarding remains intact. Read of a missing Application
Support returns unconfigured without writes; explicit save creates only that
child through a validated descriptor, then applies the existing storage checks.
Missing Library ancestors, support symlinks/non-directories/unsafe modes fail
closed. No actual user configuration was written.

Validation: `swift test --package-path Packages/ResiduePreferences` passed **22
 tests**, including the previous 18 and four new tests (unsafe support test has
three parameter cases), in 2.008 seconds. New coverage includes no-create read,
first save/reopen/update/revision conflict, unsafe child, missing ancestor,
ancestor symlink, oversize and pre-cancelled save without directory creation.
No Xcode build or fresh sandbox GUI E2E was run for this change.
