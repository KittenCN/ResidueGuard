# P0 环境基线 — 2026-09-20

本次仅核验开发环境、公开手册和 SDK。没有执行系统清理、权限请求、TCC/BTM 数据库读取、后台项采样、服务卸载或 helper 安装。P0 按写能力全部禁用进入 P1；本文件不是 P2 系统扫描验收。

## 实际环境

| 项目 | 观察结果 | 证据/限制 |
|---|---|---|
| macOS | 27.0，build 26A428 | 主任务实跑 `bash script/preflight.sh` / `sw_vers` |
| 架构 | arm64 | `uname -m` |
| 默认 developer directory | `/Library/Developer/CommandLineTools` | `xcode-select -p`；未全局切换 |
| 默认 Swift | Apple Swift 6.4 | CLT；项目采用 Swift 6 language mode |
| 默认 macOS SDK | 27.0 | CLT SDK，不等同 Xcode 构建已通过 |
| 已安装 Xcode 候选 | `/Applications/Xcode.app`，27.0 / 27A266a | bundle 元数据；精确 build 的正式发布身份尚未独立核实 |
| Xcode 许可/首次启动状态 | 初次被许可阻断；本轮复查已可用 | 后续指定 Xcode 的 preflight 成功，`xcodebuild -checkFirstLaunchStatus` exit 0；变化来源未知，代理没有接受协议 |
| 签名/公证/helper 身份 | 普通 Debug ad-hoc 签名校验通过；发布/公证/helper 未验证 | 只检查本项目构建产物，不读取或导出证书、密钥；不安装 helper |
| 最低部署版本 | 14.0（工程目标） | 不是已在 macOS 14 上测试的声明 |

[Apple 官方兼容表](https://developer.apple.com/xcode/system-requirements) 本次在线读取列出非 beta 的 Xcode 27，要求 macOS 26.6 或更高，携带 SDK 27 / Swift 6.4。版本层面与宿主兼容；安装包精确 build、许可状态和实际构建通过仍是不同条件。当前固定已安装候选；许可/首次启动门槛复查已清除，但此事实本身不证明工程构建通过。无需升级 macOS 或安装工具。

## 本次只读核验命令

- `bash script/preflight.sh`（由主任务最先执行；分项失败不能用脚本总退出码掩盖）。
- `man launchctl | col -b`，关注 domains、精确 service target、print 的非稳定输出声明。
- `man launchd.plist | col -b`，关注 Label、Program、ProgramArguments、BundleProgram。
- `man tccutil | col -b`，完整读取；只证明文档语法，不证明具体 service/client 可工作。
- 在 `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` 下读取 `SMAppService.h`、`NSXPCConnection.h`、`xpc/connection.h`。
- 在线读取官方 Xcode requirements、BTM deployment 文档、macOS 27 release notes JSON；普通 developer HTML 的 Markdown 跳转失败，release notes 使用官方 JSON 成功核验。

CLI 文档命令成功；Provider 的真实枚举/修改/后置验证均未运行。P1 的精确编译、测试与 GUI 状态见同目录任务测试报告，不能从此环境表推断通过。

## 下一个有界步骤

Xcode 许可/首次启动门槛已在本轮外部清除；用项目固定 Xcode 候选运行本项目构建/测试入口。之后若另行授权 P2，先只读来源采样并脱敏。任何 P3–P5 写能力实验都需独立快照 VM/专用账号和本项目测试软件；当前未提供，故保持 `notRun`。
