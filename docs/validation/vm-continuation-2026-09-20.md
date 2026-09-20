# VM 接续开发 — 2026-09-20

本轮完整复核 AGENTS、README 与 docs；用户已提供并授权配置测试 VM。此前“未发现 VM”只属于旧轮次盘点，不再代表当前状态。真实系统写能力仍须独立通过证据门槛。

## P2 路径边界修复

发现其他用户目录排除使用字符串前缀，而文件读取按路径分量处理：重复斜线、大小写变化和 Data 卷别名可能绕过排除。统一按词法路径分量检查，在 descriptor 层重复执行隐私边界；NUL、点分量及未独立授权的 `/System/Volumes` 别名阻断。大小写宽松比较仅用于保守拒绝，不合并文件身份。外卷和废纸篓分类复用同一检查，避免 `//Volumes` 缺失路径被误认为疑似残留。

修改：ResiduePlatform 的 SafeFiles、ScanService、CodeIdentityInspector 与 CollectorTests。新增测试先复现 6 处失败，修复后 `./script/test.sh platform` 24 项 Swift Testing 测试通过（其中一个为 3 参数输入）。测试仅使用合成临时数据，没有读取其他用户私密文件。环境 macOS 27.0 / 26A428，Xcode 27.0 / 27A266a，Swift 6.4。

限制：自定义账户主目录/非标准卷别名仍需完整授权模型；本修复未开放清理。平台实际服务实验与产品执行器验收分开记录。

## VM 基线准备

已观察 VirtualBuddy 2.2 中已安装客体桌面；通过客体正常关机，在停止状态对完整 VM bundle 创建 APFS clone 副本，保存在本地 git 忽略的受限证据目录。克隆存在、配置一致已检查；尚未将备份启动恢复，因此当前只称回滚副本已创建，不称恢复演练通过。

仅共享专用测试交换目录，未共享主目录、仓库或密钥目录。显示调整为 1920×1200 / 144 PPI。后续客体版本、用例与结果在实际运行后追加。宿主可用 codesigning identity 数量复查仍为 0；本地 ad-hoc 不等于稳定开发身份或 Developer ID。

## P2 schema 与 P4 token 失效修复

- `launch-plist-v2` 严格验证 Program/ProgramArguments、关键字符串、RunAtLoad、KeepAlive 已知嵌套类型和关联标识。CFBoolean 检查区分真正布尔值与整数 0/1。错误类型不再回退到正常程序路径，collector 保留 unknown 来源行及 partial/unparsed 覆盖；未知 KeepAlive 条件保留 provenance 并警告。新增测试先复现 33 个失败断言，修复后 Platform 28 项通过。字段依据为本机 `launchd.plist(5)`；未声称全部 launchd 语义已验证。
- Helper 纯策略旧实现只依赖重用 digest/source，服务端替换计划时可能沿用旧 token。先通过影响变更、创建时间变化复现错误接受；现每次注册生成内部 revision，旧 receipt 立即失效，恢复原计划也不复活旧 token。Security 11 项通过；仍是内存 review-only 策略，不是生产 XPC 信任验证。

## 隔离实验工具

新增 `Tests/Integration/VM` 与 `script/build_vm_fixture.sh`、`script/vm_fixture_lab.sh`。编译项目自有、120 秒自动结束的 ad-hoc 测试进程，固定 Label，校验 VirtualMac/当前 GUI 用户/回滚声明/初始无冲突/包 hash 与签名后才允许服务实验。目标为 ISO-01/04 正常路径子集：注册、运行观察、备份、精确卸载、隔离、恢复但不加载。

已运行 bash 语法检查、C Werror 编译、严格 ad-hoc 签名验证；在宿主实跑被 VirtualMac 门禁拒绝（exit 65），没有执行宿主服务动作。产物与主 App 已放入独立交换目录。当前客体停于登录页，需要用户本地登录；未把未执行的 VM 用例计入通过。

该 shell 夹具不是抗竞争产品执行器，不替代 M/S 故障与攻击矩阵；没有 Developer ID/helper 信任证据。流程与限制详见 `Tests/Integration/VM/README.md`。

## 本轮已有构建证据

`./script/test.sh core` 30 项通过；`./script/build_and_run.sh --build-only`、`--verify` 均 exit 0（BUILD SUCCEEDED / 正常 .app 进程存在）。GUI 外观工具对本 App 返回 native pipe closed，故不宣称人工外观验收完成；自动 XCUITest 单列最终结果。

## 本轮真实只读复扫

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path Packages/ResiduePlatform ResidueProbe --host-readonly` exit 0：14 条配置记录、44 个应用实例、0 高可信残留；应用索引仍 partial，三个启动源为 completeWithinDeclaredScope / partial / completeWithinDeclaredScope。runtime、BTM、登录项、TCC 来源仍 unsupported。仅输出计数，不提交软件清单或原始路径。v2 parser 已参与本次复扫，矩阵更新为本报告证据，但写能力仍全部 false。

回滚副本的 Disk.img / AuxiliaryStorage 已完成 SHA-256 读取（exit 0），摘要仅留本地。它证明副本可完整读取，不证明恢复启动成功。VirtualBuddy APFS clone/共享目录方案参考其[官方 README](https://github.com/insidegui/VirtualBuddy#taking-advantage-of-apfs)。

## GUI 最终验证与接续点

首次完整 `./script/test.sh ui` exit 65：11 项中 1 项过滤隐藏选择断言失败（98.790 秒）；加入失败时 AX 层级诊断后，针对性单项通过（9.331 秒）。不能仅据此确定瞬时失败原因。测试随后明确等待选择入口启用、搜索框实际值等于输入、目标计数发布，并额外检查过滤行不再可见；未删除原断言或放宽安全规则。最终完整 UI 回归 exit 0，11 项、0 失败，99.134 秒。该结果不承诺已根除所有间歇性问题。

本轮修复和夹具已分批 push main：`62c9280`、`1fc1c2f`；后续文档/测试同步以 Git 为准。宿主未做任何 cleanup/reset/helper 安装。VM 截图最终仍为登录页：需要用户本地登录，无需传递密码。下一步为客体只读环境确认、共享目录挂载、回滚恢复验证，再运行自有 Agent 实验并导出证据；不能将这一步改在宿主执行。

全项目未完成：真实抗竞争清理 driver、持久化 journal/恢复、签名 XPC/helper 生命周期与攻击测试、权限精确能力及正式分发仍有开发/实测缺口。宿主没有有效签名身份，Developer ID/公证也尚未具备。当前测试通过仅覆盖报告列明范围。
