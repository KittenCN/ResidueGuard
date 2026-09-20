# ResiduePreferences

本应用保留/忽略配置的私有本地存储。只保存有界 opaque Data，不解释规则、不扫描软件、不提供执行器、任意文件名或删除接口。调用方只能传入已经存在的本应用 sandbox Application Support 目录；它不是特权 helper 信任根。

```swift
let store = try RetentionPreferenceStore(applicationSupportDirectory: appSupport)
let previous = try store.read() // RetentionPreferenceSnapshot?；data / revision
let saved = try store.save(data: encodedRules, expectedRevision: previous?.revision)
```

这些是同步 I/O API，应由调用方在后台任务执行。父目录必须已存在；read 不创建配置目录或锁，未配置时返回 nil。保存只使用固定 `ResidueGuard/retention.json`，首次用户保存时创建 `ResidueGuard` 子目录。nil revision 只允许首次创建；更新必须匹配当前内容的 SHA-256 revision，过期 revision 返回 conflict，不覆盖其他窗口/实例的新值。相同内容具有相同 revision；它不是单调计数器、授权凭证或真实性签名。

## 存储边界

- 父路径拒绝 NUL/编码 NUL/过长路径，O_NOFOLLOW_ANY 拒绝任一级符号链接。父目录必须当前 UID 拥有、无组/其他用户写权限、无扩展 ACL。
- 固定子目录必须当前 UID、0700、无扩展 ACL；配置、锁、临时文件必须当前 UID、0600、单硬链接普通文件、无扩展 ACL。不自动修复不安全权限。
- 目录 fd 锚定并复核父/子 inode；锁 inode 也在读取与提交边界复核。固定 retention.lock 的 flock 序列化合作实例，等待上限 2 秒并检查取消。锁是 advisory，不承诺抵抗同 UID 已完全控制目录的恶意进程。
- 数据上限 128 KiB；版本化 JSON envelope 上限 180,000 字节。canonical JSON 不转义 base64 斜线，避免最大 binary 数据外包翻倍。读取分块有界，校验版本/hash/规范格式；损坏、未知版本、不安全文件或 I/O 错误都不是空配置。
- 保存使用同目录独占临时文件、完整写入、fsync、revision/文件身份复核、原子 rename、目录 fsync。首次创建用 RENAME_EXCL。正常失败清除本次临时文件；进程崩溃可能留下私有临时文件，不自动删除不明文件。
- rename 前取消/失败不提交新内容；rename 后取消、验证或同步失败统一返回 writeOutcomeUnknown。调用方应在新任务中重新读取当前状态，不得认为“没有写入”或自动重试旧 revision。

这是应用配置原子替换，不是源清理事务、备份还原或断电持久性认证。没有写入真实用户路径数据作为测试夹具。

## 已执行验证

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePreferences
```

2026-09-20，macOS 27.0（26A428）、Xcode 27.0（27A266a）：18 个 Swift Testing 测试通过（2.015 秒），含 2/4/2 个链接、权限和提交后失败参数案例，无跳过。全部文件/ACL/权限修改限自有随机 `/private/tmp/ResiduePreferenceTests-*` 目录。

覆盖首次保存/重开/更新、缺失不创建、过期 revision、两个独立 store 并发仅一个胜出、symlink/硬链接/目录与文件 mode/ACL、128 KiB 最大 binary、超大 envelope、损坏和未知版本、任务取消、锁超时/取消、提交前旧值保留、提交后 unknown 与重读、父下子目录及锁替换拒绝。并发测试使用两个独立实例和真实 flock；本轮未启动两个独立进程，也未测试物理断电。

详细记录见仓库 `docs/validation/preferences-storage-2026-09-20.md`。UI/规则语义由上层处理，存储包不判断某条规则是否可以绕过清理确认或保护边界。

Fresh sandbox bootstrap: the static `read(sandboxLibraryDirectory:)` and
`save(data:expectedRevision:sandboxLibraryDirectory:)` entry points accept the
app's existing sandbox Library directory and append only the fixed
`Application Support` name. Read returns nil for that missing child without
creating anything. Explicit save may create that one child with mode 0700,
using a validated Library descriptor and `mkdirat`; existing unsafe directories,
symlinks, ACLs and missing ancestors are rejected, never repaired or recursively
created. The usual bounded configuration, revision and post-rename outcome
semantics then apply. The caller must obtain Library from its own sandbox URL;
this API cannot authenticate that an arbitrary supplied directory is a sandbox.
