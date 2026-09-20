# 用户选定报告的文件读取边界（2026-09-20）

新增独立 `Packages/ResidueAuditImport`，将实际 fd 读取设计成可测试模块，避免历史页只有内存合成 UI 测试。此任务未更改 App、Xcode 工程或 ResidueRecovery；读者模块供主任务随后替换 History 私有 reader。

公开 API 只接受已由调用方显式选择的 URL，并只返回脱敏 summary。授权作用域仍由 App 拥有，本包不获取/保存额外权限。`O_NOFOLLOW_ANY` 拒绝任一级 symlink；fstat 限定当前 UID、普通文件、单硬链接。16 KiB 分块读取，总量最大为模型上限加 1；文件在初始大小检查后继续增长也受此界限约束。读前后 fd 元数据观察变化会拒绝；每块及解析前后检查取消。

实际执行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueAuditImport
```

macOS 27.0（26A428）、Xcode 27.0（27A266a）、Apple Silicon：15 个 Swift Testing 测试全部通过，最终无失败/跳过。验证的是自有真实文件和内核 fd 行为，非只用 mock。

覆盖：有效 canonical envelope 解码且仅返回脱敏结果；超大文件；末级/祖先 symlink；hardlink；目录；无 writer 的 FIFO 非阻塞拒绝；失效文件和 chmod 不可读文件；损坏与未知模型版本；真实取消的 Swift Task；读块间确定性取消；读取中 size/mode 变化；初始 stat 之后增长超过上限；NUL/编码 NUL、PATH_MAX 超长路径拒绝，以及合法文字 %00 文件名不会误拒绝。后四类用内部（非公共 API）取消检查注入点安排确定性时序，实际文件操作仍经过公开内核接口。全部夹具限自有随机临时目录，测试后清理。

普通并发变化检测不是真实性保护，也不能声称阻止拥有同 UID 完全控制权的修改者恢复元数据。没有锁定文件、没有系统清理/恢复、没有自动授权；本包测试不等于 NSOpenPanel 系统授权端到端验收。集成 diff 步骤见包 README；App 未接入前，不能把这些新增测试说成 App 已使用该 reader。

开发中先加入路径异常测试，初次因缺少显式路径校验得到 inaccessible 而失败。随后发现当前 Foundation 把 NUL 在 url.path 中保留为文字 %00，单检查原始 NUL 不足；最终同时检查 percentEncoded path 的 %00，避免混淆另一个实际文字 %00 文件。对应回归覆盖这种不同文件同时存在的情况。修复后 15 项全通过。
