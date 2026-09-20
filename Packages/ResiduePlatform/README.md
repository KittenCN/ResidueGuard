# ResiduePlatform

Swift 6 / macOS 14+ 的只读文件观察层；依赖 `ResidueCore`，不包含清理执行器。主应用继续使用 App Sandbox，需由用户授予扫描目录访问权。CLI 只读探针由明确 `--host-readonly` 参数启动。

`ScanService(configuration:).scan()` 返回不可变快照；`cancel()` 或调用任务取消都会中止有界扫描并产生明确 cancelled 覆盖。`ScanConfiguration` 注入 launchd 配置目录和应用目录。当前默认范围为当前用户 LaunchAgents、共享 LaunchAgents/LaunchDaemons，以及两个顶层 Applications 目录。不是全系统清单。

文件读取逐段 `openat(O_NOFOLLOW)`，拒绝中间符号链接、特殊文件、超大文件和读中变化；plist 按 XML/二进制解析，限制深度/字段长度。限制每类目录 16 个、单文件默认 1 MiB、launchd 原始输入总量 16 MiB、记录总数。原始 plist 至多保存前 4 KiB（Base64）与 SHA256；截断显式标注。无权限、无效、未解析配置保留来源行及错误，不能变成“没有记录”。不执行 Program/ProgramArguments。

实例索引保留重复 bundle ID 对应的每个路径、inode、device 与时间。每次扫描至多对 32 个应用通过 Security.framework 静态读取签名标识、Team ID 和 designated requirement，保留 unsigned / unavailable / metadataPresentUnverified，超限明确跳过。元数据不代表签名有效、信任或归属已验证；没有完整签名资源验证、运行时、替代安装位置和稳定复核的完整证据。直接执行文件存在只说明目标观察，不证明服务运行。外卷未获准不冒充已离线，未知归属和脚本载荷保持未知。真实扫描永不产生高可信残留；所有写入能力被策略阻断。

launchd runtime / BTM / 登录项 / 第三方权限未建立可用来源 profile，返回 unsupported。不存在 TCC/BTM 数据库直读、全量重置、helper 安装、shell 执行或第三方 SMAppService 注销。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePlatform
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path Packages/ResiduePlatform ResidueProbe --host-readonly
```

探针只输出数量与覆盖状态，不输出个人路径、软件名或原始记录。测试只创建自己的临时合成目录。主机只读探针不等同于系统清理集成、App Sandbox 授权弹窗、跨版本或隔离环境验证。

## 静态签名元数据依据与限制

`CodeIdentityInspector` 依据本机 macOS 27 SDK 的 `SecStaticCode.h` / `SecCode.h` / `SecRequirement.h` 使用公开 `SecStaticCodeCreateWithPath`、`SecCodeCopySigningInformation`、`SecRequirementCopyString`。SDK 明确说明 CopySigningInformation 成功不等于签名有效；因此未调用全量资源校验，也从不输出 verified。不请求网络访问，不运行目标程序。对 bundle、Info.plist、主执行文件和存在的签名 envelope 使用 no-follow 检查，限制文件大小，并比较执行文件 inode/device/size/mtime 的前后观察。

Security.framework 同步调用不提供本实现可强制的超时或中途取消；只在调用前后取消检查，并限制每扫描调用数。元数据读取不是抵御所有并发修改的事务性证明，不能用于执行授权。测试使用自建未签名脚本 app、重定向执行文件、其他用户/外卷拒绝；不是签名证书或 XPC 握手验收。
