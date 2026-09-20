# 本地 Release 签名边界

2026-09-20，macOS27/26A428，Xcode27/27A266a。此任务不要求 Developer ID、App Store 或公证。

原 Release ad-hoc 构建成功，但实际签名仍注入 `com.apple.security.get-task-allow=true`。按本机Xcode规格及[Apple签名问题说明](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)，Release单独设置 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`。首次重建发现这一设置同时移除了自动注入的沙盒声明；因此没有将该中间产物作为可用结果。最终新增显式 Release entitlements，仅保留原有 App Sandbox 和用户所选文件只读两项。

实际最终验证：

- `./script/build_and_run.sh --release-build-only` 成功，生成本地 ad-hoc Release；不自动启动或分发。
- `script/verify_local_release.py` 在 x86_64 与 arm64 两个切片分别验证 strict签名、ad-hoc + runtime标志和精确两项沙盒权限；没有调试授权、网络权限或读写目录扩权。
- 二进制没有三个 History UI 注入flag；这只是这些入口的构建检查，不替代全部功能验收。
- 同一校验脚本对现有 Debug 包明确退出1（Unexpected Release entitlements），负例真实生效；Debug保持原调试配置。

Intel仅编译/签名切片验证，未在Intel设备运行。Release进程已实际启动；GUI内容和真实系统picker验收暂未完成；当前CUA native pipe异常不算成功。ad-hoc资源封包与Hardened Runtime不证明开发者身份、Gatekeeper分发信任、公证或helper授权。未安装证书，没有改宿主信任库，也没有以发布门检查阻断本地开发。
