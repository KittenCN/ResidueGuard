# 真实 VM 沙箱目录扫描验证

环境：VirtualBuddy Quickest Loris，macOS 27.0 / 26A428 / arm64；宿主 Xcode 27.0 / 27A266a。使用正常 ad-hoc sandboxed `.app`，没有扩大 entitlement，没有关闭沙箱/SIP。当前工作为本地开发，不依赖 Developer ID。

## 实际发现与修复

通过客体 NSOpenPanel 选择自有 ISO-01 plist 所在的当前用户 LaunchAgents 目录：取消时仍为配置目录 0、未扫描；确认时配置目录 1，未自动扫描。旧版随后扫描返回 0 行，coverage 明确 permissionDenied / POSIX 1。

根因定位为 `SafeFiles.descriptor` 从 `/` 开始用 O_RDONLY 逐级打开上级目录，要求了所选目录授权之外的上级目录读取权限。改为一次 `open(path, O_NOFOLLOW_ANY | O_RDONLY | O_CLOEXEC | O_NONBLOCK)`，目录增加 O_DIRECTORY。内核拒绝路径任意分量的符号链接，仅打开所需目标。依据本机 `man 2 open` 与 SDK sys/fcntl.h；系统调用失败仍显式拒绝，没有回退为跟随链接或扩大权限。

开发时先尝试同时使用 O_NOFOLLOW 和 O_NOFOLLOW_ANY，实际得到 EINVAL，Platform 出现 19 个断言/错误；去掉相斥的 O_NOFOLLOW 后，全部 38 个测试通过，包括文件及祖先 symlink 拒绝。没有将失败轮次当通过。

重新构建、strict codesign 验证并复制至 VM 独立测试 app，重新选择同一目录后真实扫描返回 **1 条**自有配置记录。用户启动代理页显示固定 fixture 名、不可勾选，目标显示“未能核实：无访问权限”，未被标为高可信残留：仅配置目录被授权，并未授权可执行文件目录。没有运行被扫描程序。

概览改为“本次返回 N 条记录”，并在 coverage 不完整时明确提示“记录总量未知”，避免读失败的零行被误解为完整空列表。

## 结果与限制

- 真实 NSOpenPanel 取消、授权、显式扫描：passed。
- 所选目录内自有 plist 可读：passed；不是全磁盘扫描验收。
- 未授权目标不误标高可信残留、真实行不可执行：passed。
- 其他 OS/build、其他用户、BTM、TCC、完整 GUI 可访问性：notRun/unsupported，不能推广。
- 客体时钟显示与宿主有时区差异；报告使用宿主日期，未据此推断计划有效期或跨设备时间一致。

苹果官方沙箱授权说明：[Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)。目录授权只赋予所选范围；这次修复没有增加任何额外授权。
