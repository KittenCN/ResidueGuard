# ResidueGuard｜macOS 残留管家
## 只读扫描与 dry-run 原型 · 2026-09-20

本仓库包含研发规格、原生 SwiftUI macOS App 工程和独立 Swift 6 核心 Package。当前提供用户明确授权目录内的真实只读启动配置扫描、明确标记的合成演示和 dry-run 计划；不包含可用的真实清理执行器，不申请隐私权限、不安装后台组件。实测与未验证项以 `docs/validation/` 为准。

本地操作步骤见[使用说明](docs/local-user-guide.md)。

### 开发入口

- `bash script/preflight.sh`：只读环境预检。
- `./script/test.sh core`：使用项目选定 Xcode 的 Swift 工具链测试独立核心，无系统副作用。
- `./script/build_and_run.sh`：使用项目固定 Xcode 构建并以 `.app` 启动；`--build-only` 只构建，`--verify` 按本项目可执行文件路径核验启动进程，不误认其他同名构建。
- `./script/build_and_run.sh --release-build-only`：构建并核验本地 Release；保留只读沙盒，不带调试授权，无需 Developer ID。
- `./script/test.sh platform`：独立只读采集与进程边界测试。
- `./script/test.sh quarantine`：同一 ResidueBackup package 内的隔离 target，测试自有临时夹具隔离、恢复冲突、只读恢复及固定实验流程。
- `./script/test.sh recovery`：只读历史审计模型、完整性与脱敏测试。
- `./script/test.sh preferences`：保留规则私有配置、原子保存、并发冲突与新沙盒初始化测试。
- `./script/test.sh audit-import`：真实文件有界读取、链接拒绝与取消测试。
- `./script/test.sh backup`：只运行备份 target 的源备份、manifest 与篡改拒绝测试。
- `./script/test.sh transactions`：真实 SQLite 与无副作用事务驱动的集成测试。
- `./script/test.sh persistence`：系统 SQLite 持久化日志测试，仅操作测试自有临时目录。
- `./script/test.sh security`：无副作用的 helper 协议与身份/token 策略测试。
- `./script/test.sh ipc-model`：只测试独立 XPC 实验的帧、预算和会话绑定模型，不启动真实 XPC 或 helper。
- `./script/package_local_release.sh`：创建本地 Release ZIP 与 SHA-256 清单，解包后再次检查签名；不安装、不上传、不公证。
- `./script/package_preview.sh`：创建本地 Debug 预览压缩包，不是正式发布。
- `./script/release_check.sh`：只读发布门禁检查，当前预期阻断。
- `./script/test.sh ui`：Xcode UI 测试，只操作本应用；系统文件选择器端到端用例需显式环境开关，默认跳过。
- Codex Run 已连接到同一构建脚本，不修改全局 `xcode-select`。

首次打开不会伪装成已扫描系统。主动载入演示后，复选框表示合成 dry-run 目标；预览/确认均不执行主机写操作。权限页面明确显示读取限制和系统设置文字路径。应用关联页保留每个观察到的安装实例、候选关联与冲突；这些线索不证明归属或卸载。记录详情可显式保留30天，保留规则不隐藏记录、不改变存在判断；演示规则不持久保存。

详见 [阶段状态](docs/validation/status.md)、[环境与工具链](docs/validation/environment.md)、[实际测试报告](docs/validation/test-results-2026-09-20.md)。真实写入必须满足后续隔离验证门槛；当前系统修改能力全部关闭；显式添加保留规则只保存本应用配置。

### 产品目标
在原生 macOS GUI 中，按登录项、后台项、启动服务和权限类别展示已知记录。通过多来源证据识别卸载残留；软件名前有清理复选框；高可信残留以红色和文字标识。实际影响对象全部是高可信残留时，应用内确认一次；只要实际影响到仍安装的软件，就必须确认两次。管理员认证不替代这两次产品确认。

### 必须先知道的边界
“记录存在”“软件存在”“能够安全清理”是不同问题。不可将所有页面都有菜单入口，等同于所有页面都能读取完整系统列表或逐项删除。尤其 macOS 27 已明确限制直接访问 TCC 数据库 [S03]；不允许把旧版读库方案当作新系统功能承诺。详见 `docs/00-feasibility.md` 和 `docs/08-sources-and-decisions.md`。

### 阅读顺序
1. `AGENTS.md`：Codex 必须遵守的项目约束。
2. `docs/00-feasibility.md`：真实能力边界和首期交付范围。
3. `docs/01-product-ui.md`：页面、字段、状态、交互和用户文案。
4. `docs/02-architecture.md`：工程结构、模块边界、模型、接口和并发。
5. `docs/03-providers-and-detection.md`：数据采集、应用识别和残留判断。
6. `docs/04-cleanup-security.md`：确认状态机、清理事务、安全和恢复。
7. `docs/05-roadmap.md`：按阶段拆分的任务及完成门槛。
8. `docs/06-tests-acceptance.md`：可逐项验收的测试清单。
9. `docs/07-build-release.md`：环境、签名、构建、发布与自卸载。
10. `docs/08-sources-and-decisions.md`：来源、证据强度、架构决策。
11. `docs/09-codex-prompts.md`：首次启动和后续阶段的可复制提示词。

### 首次使用
将本目录作为新项目根目录交给 Mac 上的 Codex。不要与已有业务项目混放。先让 Codex 读取约束，执行 P0 的只读环境核验，再建立原生工程。不要一开始要求“全功能一次完成”。

可在终端运行 `bash script/preflight.sh` 查看环境。脚本不请求 sudo、不安装工具、不读权限数据库、不运行后台清理命令、脚本自身不创建输出文件或修改配置（系统工具可能维护自身缓存）。开发工具不全时只打印缺失，不自动修复。

`templates/capability-matrix.template.json` 是未验证模板，不是兼容性测试结果。`fixtures/confirmation-cases.json` 是合成测试数据，不包含用户真实软件列表。

### 交付优先级
首个可用版本优先实现：真实只读扫描 → 高可信残留识别 → 用户级启动配置的精确隔离清理 → 双确认和恢复。权限模块始终具有“能力不足、系统设置引导”的正确降级，不以绕过系统保护换取表面完整。

### 术语
- 登录项：用户登录后打开的应用或项目。
- 后台登记：系统对后台活动/辅助程序的登记，不等于正在运行的进程。
- 启动服务：launchd 配置及对应的运行时服务。
- 权限记录：隐私授权的已知记录，不等于实时有效访问能力的完整真相。
- 清理：移除明确选择的登记/配置，或重置明确支持的授权范围；不是删除用户文件或卸载整个应用。

所有来源标号 `[Sxx]` 在 `docs/08-sources-and-decisions.md` 中解析。

最新只读范围与限制见 [P2 验证记录](docs/validation/p2-results-2026-09-20.md)，整体剩余门槛见 [项目进度](docs/validation/project-progress.md)。

完整使用步骤见 [只读版本使用说明](docs/user-guide.md)。本轮综合证据见 [开发验证报告](docs/validation/final-development-results-2026-09-20.md)。

当前以[本地开发验收范围](docs/validation/local-development-scope.md)为准：暂不推进 App Store、Developer ID 或公证发布；这些不是只读功能和隔离测试的开发前置条件。

固定自有VM备份/隔离/恢复实验入口的架构与运行限制见 [受限实验上下文](docs/validation/owned-fixture-context-2026-09-20.md)。它不接受路径参数、不修改服务登记、不接主App生产gate；构建和单测不代表客体实验已通过。
