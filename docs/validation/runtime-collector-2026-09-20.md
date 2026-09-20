# 精确当前用户运行状态采集连接层

验证环境：macOS 27.0 / 26A428，Apple Silicon；固定 `/Applications/Xcode.app/Contents/Developer`（Xcode 27.0），Swift 6 模式。

新增 `LaunchRuntimeCollector`，默认 disabled。调用方必须显式选择 parser profile；真实生产构造器自行读取 OS major/build 和 uid，不允许调用方伪造环境或注入任意命令。已验证 profile 仅为 `launchctl-print-gui-26A428-v1`。未知 OS/build/profile 在启动进程前返回 unsupported；另一个用户、root、异常 Label、非 LaunchAgents 来源、非规范/外部卷/废纸篓/其他用户路径拒绝。仅一次 typed `/bin/launchctl print gui/<current uid>/<Label>` 调用，无 shell、无域枚举。

采集后由既有严格 parser 比对 Label/domain/path/program。取消前不启动；采集过程中取消，即使捕获结果可解析也退回 unknown/cancelled。capture failure 名称保存在不含原始环境输出的 provenance。超时、权限/进程失败、输出截断、未知文本和身份冲突不能变成“未注册”或“未运行”。

执行验证：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePlatform
```

38 个 Swift Testing 测试通过（包含 6 个新增 collector 测试）。测试包括默认关闭和 profile/OS/uid gate 不调用 runner，精确关联正常值，失败/截断/未知格式/身份冲突，以及调用前和调用中取消。既有 DiagnosticProcessRunner 测试真实运行固定只读工具及受控 sleep/yes 测试子进程，验证超时、取消、输出上限。Collector 状态关联使用已脱敏 VM 文本夹具和内部 runner 注入；未把夹具验证冒充新的 VM OS 集成。

边界：本层尚未接入 GUI 或 ScanService 的默认全量扫描；没有扩大 sandbox 权限，也没有新增真实宿主服务查询或修改。运行状态只是在指定服务范围的一次观察，不是签名/归属证明，不改变残留判断和任何 mutation gate。当前版本不枚举配置缺失的 runtime-only 服务；未知其他系统 build 保持不支持。

## 固定客体探针

`ResidueProbe --vm-fixture-runtime` 仅接受这一个完整参数；要求真实 `hw.model` 前缀 VirtualMac 且 uid 非 root。身份固定为当前用户自有 ISO-01 fixture 的 Label、LaunchAgents plist 和实验 executable，不接受额外路径/Label/profile 参数。只输出 state/coverage/captureFailure/exitCode/profile 和计数，不输出用户名、路径、原始诊断。即使服务打印失败，也固定声明 `absenceProven=false`。

构建 `swift build --package-path Packages/ResiduePlatform --product ResidueProbe` 成功。宿主命令行验证：空参数、未知参数、额外参数均退出 64；VM 模式在真实宿主拒绝并退出 77，未启动服务查询。此时客体实际运行尚由主任务进行，不能以宿主 gate 测试替代。

## 客体重启后的实测与 profile 回归

主任务在相同 VirtualMac/26A428 客体运行固定探针，初次结果为 `runtimeState=unknown coverage=partial exitCode=0`。完整捕获成功但严格 parser 因新字段 `job state = uninitialized` 拒绝，符合 fail-closed；不能根据 exitCode=0 把 unknown 改成“未注册”。新原始样本仅保存在忽略的本地证据目录，提交夹具替换用户名和随机 socket 标识。

本机 `man launchctl` 的 print 段落说明输出不是 API，可能无预告变化；本机 `man launchd.plist` 将 RunAtLoad 定义为加载时是否启动一次，没有把 false 定义成禁止加载。未找到 job state 的稳定公开语义，因此本次仅接受实际观察到的 `uninitialized` 字面值及对应上下文（state=not running、active count=0、runs=0、无 pid）；未知值、重复字段、矛盾上下文依旧拒绝。运行状态仍依据既有 state/count/pid 和精确身份匹配，不使用 job state 做残留或可清理推断。

[Apple Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) 说明用户登录时加载 LaunchAgents 目录的配置。这与本次客体观测一致：恢复到 LaunchAgents 的 plist 在重新启动/登录后重新登记，RunAtLoad=false 使该 fixture 没有随加载运行（本次 runs=0）。以前 after-restore 的未登记证据只覆盖当时同一会话，不跨重启成立。

新增回归先确认失败（expected registeredNotRunning，实际 unknown），修复后完整 Platform 39 项通过，包括未知 job state、重复字段、state/count/runs/pid 冲突及未知 build。`swift build --package-path Packages/ResiduePlatform --product ResidueProbe` 用于更新客体探针；修复后的实际 VM 复跑结果由主任务记录，单元测试不冒充实测。

## 主任务客体复跑

修复后的 probe 从客体本地副本运行，exit 0：`runtimeState=registeredNotRunning coverage=completeWithinDeclaredScope parsed=1 unparsed=0`；`absenceProven=false signingIdentityProven=false`。仅固定 ISO01 精确服务。此前在专用共享卷上原位替换可执行文件后一次执行被客体 Killed，未得到有效结果；改为新文件名传输、客体本地新目录复制并 strict codesign 校验后运行成功。未将失败当成服务状态证据，也未关闭代码签名保护。
