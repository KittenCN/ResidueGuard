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
