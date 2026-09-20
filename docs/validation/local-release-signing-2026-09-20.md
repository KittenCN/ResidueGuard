# 本地 Release 签名边界

2026-09-20，macOS27/26A428，Xcode27/27A266a。此任务不要求 Developer ID、App Store 或公证。

原 Release ad-hoc 构建成功，但实际签名仍注入 `com.apple.security.get-task-allow=true`。按本机Xcode规格及[Apple签名问题说明](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)，Release单独设置 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`。首次重建发现这一设置同时移除了自动注入的沙盒声明；因此没有将该中间产物作为可用结果。最终新增显式 Release entitlements，仅保留原有 App Sandbox 和用户所选文件只读两项。

实际最终验证：

- `./script/build_and_run.sh --release-build-only` 成功，生成本地 ad-hoc Release；不自动启动或分发。
- `script/verify_local_release.py` 在 x86_64 与 arm64 两个切片分别验证 strict签名、ad-hoc + runtime标志和精确两项沙盒权限；没有调试授权、网络权限或读写目录扩权。
- 二进制没有三个 History UI 注入flag；这只是这些入口的构建检查，不替代全部功能验收。
- 同一校验脚本对现有 Debug 包明确退出1（Unexpected Release entitlements），负例真实生效；Debug保持原调试配置。

Intel仅编译/签名切片验证，未在Intel设备运行。Release进程已实际启动；后续在VM复制后strict验证、GUI启动与真实系统picker导入也通过，见history-report-import-2026-09-20.md。宿主CUA native pipe异常没有计入成功。ad-hoc资源封包与Hardened Runtime不证明开发者身份、Gatekeeper分发信任、公证或helper授权。未安装证书，没有改宿主信任库，也没有以发布门检查阻断本地开发。

## 本地 Release ZIP

`./script/package_local_release.sh` 已实际执行成功：构建 Release、核对能力矩阵中的生产 mutation 关闭、检查双架构签名与只读 entitlement，生成 ZIP 后解包到独占临时目录，再次执行严格签名/授权检查；最后才替换 `dist/ResidueGuard-local-release.zip` 和 `dist/local-release-manifest.json`。临时解包目录退出时清理。清单记录 ZIP SHA-256、源码提交、工作区是否有未提交变更以及未公证/未验证跨机 Gatekeeper 的事实；不上传、不安装或修改信任设置。

这是本机/隔离实验用 ad-hoc Release，当前功能为只读扫描、演示预演、历史摘要导入和显式保留规则。不要求 Developer ID；没有声称可绕过另一台 Mac 的下载信任检查，Intel 仅构建和签名验证。

同一 ZIP 随后在 VirtualBuddy 测试客体中校验 SHA-256、解包并以 `codesign --verify --deep --strict --all-architectures` 通过，再从独立自有路径启动。真实 GUI 显示“本地规则已读取”和空本地规则状态，验证最终取消/父目录读取接入未破坏现有沙盒配置读取。此 VM 验证是本地共享文件传输，不等价于带下载 quarantine 属性的公开分发验收。
