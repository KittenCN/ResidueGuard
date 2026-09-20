# 固定 ISO01 精确 bootout 实验设计（已编码，VM 待主任务验收）

范围：仅专用 VM 自有 ISO01 的单次注册卸载实验，生产 gate 关闭。首轮不串联隔离、恢复或 bootstrap；将服务变更与文件变更分开验收，避免错误的后置“缺失”判断继续触发文件移动。本报告及后续编码阶段未执行任何服务命令或修改。

## 已核验依据

本机 `man launchctl` 明确 bootout 接受 service-target；缺少服务参数的 domain-target 可以移除整个域。因此固定 argv 必须恰好为 `["bootout", "gui/<actual uid>/example.residueguard.fixture.iso01"]`，禁止路径形式、域形式、多个目标、环境/用户输入扩展。同一手册明确 print 输出不是 API，格式可无预告变化。GUI 与 user 域服务集合不同，失败不得切换 user/system 域尝试。

[Apple launchd 编程指南](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) 说明 per-user agent 的作用域与登录时加载配置机制；这是机制背景，不替代当前 build 的 bootout 集成验证。docs/04 4.5–4.6、docs/06 M03/M08/M11 要求动作日志、失败停止、恢复不启动服务。

既有 VM shell 实验记录过精确 bootout 成功；后续实际重启又观察到 registeredNotRunning。当前 parser 只支持 running / registeredNotRunning / unknown，所有失败 print 都是 unknown。旧报告“恢复后未加载”只对当时成立，不跨重启，也不能直接成为新 absence profile。

## 固定入口与前置条件

独立零参数 CLI，仅一个编译固定操作；无通用命令 public API，不复用 ReadOnlyDiagnostic 的语义伪装修改。环境门禁必须最先通过，失败不创建实验目录、不执行诊断工具：真实 VirtualMac*，getuid 非零且等于 geteuid，macOS 27.0.0 / 26A428。固定 `/bin/launchctl` 的系统工具身份检查；不提权。

固定当前账户 passwd home、LaunchAgents plist 和 ISO01 程序，no-follow 目录锚点。验证 source/program 文件身份、摘要、元数据、父目录 identity，plist 精确 Label/ProgramArguments，RunAtLoad=false / KeepAlive=false。程序签名有效且 identifier 精确匹配；ad-hoc identifier 本身不证明开发者身份，仅适用于已受控 VM 自有夹具，不能推广为第三方授权。

动作前要求现有 parser 精确关联服务为 registeredNotRunning（首轮不测试运行中进程终止）。未知、冲突、running、截断或不完整采集均拒绝。验证备份内容/metadata/manifest/根 identity，并将固定源和程序身份、备份 receipt、UID/Label、profile、观察代次绑定到短期实验计划。

## 顺序与持久记录

1. 创建并 fsync 实验计划与已验证备份；生成唯一 plan/attempt UUID，有效期建议 120 秒，不自动延长。
2. 在独立实验日志中 durable 写入 bootout intent；它表示“可能即将发出”，不是已执行。日志提交失败不得发命令。
3. durable await 返回后重新采集精确 runtime；最后一次 await 之后同步复核 source、program、目录与备份身份，再检查期限/取消。进程创建前再次检查取消。没有 API 能把 launchd 服务身份与 bootout 原子比较交换；残余竞争风险必须注明，只允许隔离自有夹具实验。
4. 仅一次固定 bootout，建议命令预算 5 秒、stdout/stderr 各 16 KiB，直接 Process argv，不经 shell。独立记录 launch failure、取消、超时、超量、退出码/termination reason、实际耗时、摘要。超时/取消结束自己启动的 launchctl 子进程，不等于撤销 launchd 已接受的动作；没有 bootstrap 补偿。
5. 先 durable 保存命令 outcome，再在独立短预算进行一次固定 print 后置观察并保存 provenance。取消发生在发出后仍尽力保存已知 outcome；若不做后置采集，明确 cancelled/notObserved，不能表示已恢复或未执行。
6. journal outcome 写失败即结束，intent 保留 pending/actionOutcomeUnknown；下次只读观察，不自动重试。命令非零、超时、未知后置都停止，不扩大、不换域、不尝试 unload/disable，不继续隔离配置。

已提交 intent 后、尚未启动工具时 freshcheck/取消失败可记录明确 notIssued 与原因；工具是否已发出不能确定时必须 unknown。一次 outcome 不能因重启重写为成功。记录 UTC 时间与单调 elapsed，不把墙钟倒退当作延长有效期。

## 为什么需要独立实验日志

现有 OwnedFixtureExperimentJournal profile 绑定 isolation/restoration 两阶段，envelope 声明 registration=noMutation，并以文件效果和 runtime Bool 约束后续恢复。不能把 bootout 塞入该记录或改动旧 noMutation 字段解释。

建议独立固定 bootout 实验 record/table/file 与版本，保留现有日志不变。记录 plan/attempt、intent、issued/notIssued/unknown、命令 capture、postObservation、source/backup/program identity；所有记录仍 authorizesMutation=false。只读重开不构造 trusted receipt、不恢复服务。

runtime provenance 至少包含 UUID generation、providerID、gui UID scope、native Label、OS build、parser profile、observedAt、stdoutSHA256、exitCode、captureFailure、outputTruncated、coverage 和 state。普通报告只显示固定标识/摘要与状态，不带 home/path/原始 stdout。受限 VM 原始诊断单独留存用于脱敏 fixture。

## 后置缺失不能推断

首轮 `bootout exit 0` 最多表示命令完成；后置 print 非零仍按当前 parser unknown，不能改成 absent。保存完整退出码、两流、无截断、工具失败状态及精确 target 上下文；只有获得真实样本并核验“服务未找到”与“域不存在/权限不足/格式变化”的区别后，才另行审查固定 build 的 diagnosticNotFound profile。即使支持此观察，也只声明本次指定服务查询未找到，不证明 App 卸载、BTM 历史删除或永久不会重新注册。

首轮成功标准应是“门禁、备份、durable intent、精确单次调用、outcome/后置原文留存、只读重开一致”流程验收；服务 absence 验收单独列未验证，不能为了完整 PASS 降低 parser。

## 最小真实验收步骤（待主任务验收）

1. 先保存当前 VM 快照和现有自有 fixture；仅只读确认当前服务 registeredNotRunning、源/程序签名与备份可验证。若前置不符，停止，不自动 bootstrap 制造条件。
2. 复制新 probe 到 VM 新目录、核验其签名，零参数执行一次，保存私有 JSON、journal 与原始后置诊断；不在宿主运行。源 plist 和程序必须原地保留，文件身份/摘要再次比对未变。
3. 第二个只读进程重开独立 journal，确认意图与 outcome 关联、单次调用、无文件 mutation、无 bootstrap；不能把诊断未找到直接判为完整删除。
4. 对原始后置输出制作脱敏 fixture并独立评审，再决定是否存在可信的 scoped diagnosticNotFound 观察。没有样本或字段不明则保留 unknown。

宿主纯测试应先覆盖参数/环境拒绝零执行、prepare失败零执行、最后 await 中身份变化拒绝、过期/取消、命令失败禁止后续动作、超时可能已执行、写 outcome 失败保留 pending、重启只读不重放、未知 print 不变 absent。真正 crash-in-flight 如需 VM 第二轮，应从独立快照恢复受控前置状态；不在同一运行中自动重试。

本设计不包含启动夹具、终止运行中服务、隔离配置、恢复加载、生产 GUI 同意流程或 helper。生产能力仍关闭。


## 编码交付与实际测试

新增独立 `ResidueOwnedFixtureBootoutProbe` target；实现位于 `OwnedFixtureBootoutProbe.swift` / `OwnedFixtureBootoutTransport.swift` / `OwnedFixtureBootoutLog.swift`。没有改现有 noMutation journal、共享 createISO01 工厂或生产入口。环境门禁先于创建实验根；捕获实现只接受内部 bootout/print 枚举，固定 `/bin/launchctl` 与当前 UID 的 ISO01 target，不接受 path/argv。

独立 JSON evidence 用固定 intent/preflight/outcome/observation 文件名，O_EXCL + O_NOFOLLOW + 0600，文件 fsync/F_FULLFSYNC、目录 fsync；禁止覆盖和自动续跑。写失败可能留下不完整文件，必须作为未知证据，不作为可恢复计划。尚无通用导入/恢复/授权 API。intent 绑定 source/program fingerprint、备份摘要/root identity、runtime provenance；prepare 后 fresh runtime 也独立留存。最后 await 后再次复核 sourceRoot、source、程序、backup 与期限/取消。后置 raw capture 仅留本地实验文件，普通 stdout 无个人路径。

命令 budget 5 秒；bootout 双流各 16 KiB，print stdout 256000 bytes、stderr 16 KiB。取消/超时只结束本探针创建的 child，不能撤销已发出的 launchd 请求。非零退出、超时、日志错误停止，不重试、不隔离、不 bootstrap。post print 无论结果均保留 unknown/absenceProven=false，不通过未经验证的 absence profile。

实际命令与结果：
- `swift test --package-path Packages/ResidueBackup --filter ResidueQuarantineTests`：66 项通过（含最初 7 项 Bootout 测试）；随后新增失败退出/顺序测试，targeted `--filter OwnedFixtureBootoutTests` 9 项通过。
- `swift build --package-path Packages/ResidueBackup -c release --product ResidueOwnedFixtureBootoutProbe`：通过。均指定 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
- 宿主 release 零参数仅门禁拒绝 exit 77，传 --help 拒绝 exit 64；未运行 launchctl，没有源操作。
- `git diff --check` 通过。

测试使用本地随机临时目录及注入 capture 结果，覆盖独占durable文件、symlink/覆盖拒绝、prepare失败零调用、fresh失败notIssued、取消零调用、已发出超时保存后停止、命令非零不重试、outcome写失败停止、正常durable顺序。真实 bootout/print transport 行为和崩溃中的服务效果仍未在本轮运行；不把纯测试作为 OS 验收。

release：`Packages/ResidueBackup/.build/out/Products/Release/ResidueOwnedFixtureBootoutProbe`。主任务应先审查并准备 VM 快照，再自行决定实际运行；本交付没有执行真实服务变更。


### 主任务首轮 review 后收紧

Transport 移除 Task.detached：仅独立 CLI 使用的有界同步 capture，在真正 Process.run 前执行内部同步 finalCheck，随后检查 cancellation，不留另一个异步调度边界。最终 sourceRoot/source/program/backup/expiry 验证都在此处；不提供 public callback。无 UI 使用此实现。

日志现在封装 canonical version/attempt/slot/payload/SHA256 envelope，payload base64 有界（2 MiB），每槽文件 3 MiB；这用于完整性和关联检查，不是对拥有本账户写权限者的认证。根及文件均检查 ACL/flags/owner/mode，文件须单链接；根当前 no-follow 路径和 fd identity 绑定，读取前后验证文件 identity/size/mtime/ctime。严格只读实例禁止 append，固定文件 O_RDONLY 重开、不修复不创建sidecar；错误 attempt、错误slot、未知version、缺失intent的后续槽、不完整JSON/摘要失配均拒绝。正常流程最后以独立 readOnly 实例重开四槽。

新增测试覆盖 readOnly 拒写、错误attempt/slot、损坏、hardlink、根flags/替换；Bootout targeted 12项通过。最终全 Quarantine 71 项通过；最终 release 重建通过（依赖 OwnedExperimentStorage 有既有 String(cString:) deprecated 警告，本轮未改该文件）。最终宿主门禁复查仍为零参数 77 / 传参 64，diff 检查通过。没有新增真实服务执行。


### 原始字节摘要与 CLI 退出语义修复

实际管道捕获直接以 stdout/stderr 原始 Data 计算 SHA256，再做 UTF-8 替换解码用于本地展示。新增非法 UTF-8 纯测试证明摘要不等于显示字符串重编码的摘要；截断时摘要明确仅代表捕获的有界字节片段。

CLI 参数拒绝 exit 64；只有真实环境门禁拒绝 exit 77，并输出 mayHaveExecuted=false。其他停止统一 exit 65，输出 mayHaveExecuted=unknown / noAutomaticRetry=true，不能把命令可能已发出后的超时/取消/日志错误冒充环境拒绝。日志 capture.launched 与具体 failure 提供进一步证据。

此次最终全 Quarantine 72 项通过（Bootout 13 项），release 构建通过；宿主实际零参数 exit 77 环境拒绝，传 --help exit 64。未运行宿主 launchctl 或 VM 服务操作。diff 检查通过。
