# 固定服务诊断未找到：只读研究

2026-09-20。主任务提供的VM观察：固定ISO01 bootout返回0后，在同一gui/501下查询固定Label，print返回113、stdout空、stderr为`Bad request.`及精确匹配Label/UID的`Could not find service`诊断，无capture failure或截断。本研究未独立重跑该观察，没有运行任何本机/VM命令、改变注册状态或修改parser。

结论：当前parser保留unknown正确。可以设计独立的`scopedDiagnosticNotFound`**诊断类别**，仅表示“指定build/profile、调用上下文、域和Label的一次查询产生已识别的未找到诊断”；不能等同runtime absent、全部域未注册、应用卸载、配置文件已删除或清理完成，也不能据此跳过bootout或授予文件移动能力。建议保持runtime.state=unknown、coverage=partial，并在独立diagnostic字段携带历史证据，避免名字让调用方把诊断误当存在性事实。

官方资料边界：本轮查到的[Apple公开launchctl手册源](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchctl.1)是旧接口说明，不能为26A428的print错误格式或113给出稳定契约。[Apple启动服务指南](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)区分配置、登记和按需运行，支持这些概念不能互相替代；未找到Apple公开契约承诺该exit/stderr组合是跨版本机器可读的服务不存在证明。Apple论坛讨论不是这种稳定API承诺。不把113擅自解读为某个POSIX/Mach/bootstrap错误码域。

最低补充只读VM对照（尚未执行）：

| 对照 | 验证目的 |
| --- | --- |
| 当前已登录用户GUI域的独立可达性观察 | 区分域不可达和域内Label未找到；同UID/同调用会话、紧邻查询，完整有界capture。即使成功也不是两次查询的原子一致性证明 |
| 同一存在GUI域、从未创建的固定测试Label | 看是否与bootout后的诊断完全一致，避免把“刚执行过bootout”当parser必要前提 |
| 合法但确认没有GUI会话的VM测试UID域 | 区分缺失域；不要探查另一个真实用户的数据，也不要仅用越界UID代替此对照 |
| 非法domain语法、缺失Label、错误domain种类 | 区分Bad request/usage与精确Label未找到；错误类型相同也不能提升为不存在证明 |
| 同固定Label在user域与gui域的只读查询 | 确认域隔离，不能从gui未找到推出user/system也没有；只查询自有固定Label，不枚举第三方服务 |
| 已有固定自有registeredNotRunning服务的查询（若VM当前存在） | 正向对照；若不存在，不为此研究bootstrap任何服务，标记待后续已授权实验提供 |
| 相同输入重复查询、C与可用本地化环境、runner本地/SSH上下文 | 确认编码/locale/上下文影响；任何未验证上下文保持unknown，不把一次匹配推广到全部调用环境 |

所有对照保存OS build、当前UID、上下文标识、目标、开始/结束时间、退出码、stdout/stderr摘要、failure、截断及匹配结果；不把完整域输出或个人路径带入git。域对照如会输出服务清单，应在专用VM内有界捕获、仅提取域可达证据，避免留存不必要记录；不作为全量服务枚举入口。

解析器负例另用纯fixture测试：错误UID/Label、前后缀额外文本、stdout非空、exit不符、timeout/cancel/permission/launch failure、截断、未知build/profile、非精确换行/编码都不得产生该诊断类别。验证矩阵成立后仍仅给固定profile的诊断匹配，不升级写入gate。bootout返回0是命令结果，随后未找到诊断是另一条时间点观察；二者组合也不能推出源配置/应用删除或未来不会重新登记。

## 有界实现：仅已观察诊断文本

2026-09-20：`LaunchRuntimeParser` 现在只在现有 27/26A428/profile 白名单内，把一次完整捕获的 exit 113、空 stdout、精确两行英文 stderr（包括末尾 LF）记为 `rawMetadata.observedDiagnostic=scopedServiceLookupText26A428`；其他情况为 `unclassified`。匹配要求正 UID、有限 ASCII Label，以及诊断内精确相同 gui UID/Label。此名称刻意表达观察到的文本，不定义 semantic not-found。这没有验证域可达性、调用会话或跨 locale 稳定性；上表 VM 对照仍未执行。

匹配后 runtime 仍 unknown、coverage partial、parsedCount 0、unparsedCount 1、targetReferences 空。没有新增 absent 状态、执行能力或归属输入，也未改变任何 absenceProven 字段；只增加诊断解释。错误 exit、stdout 非空、错误 UID/域/Label、本地化、CRLF、缺失/额外换行、重复文本、未知 profile/build、截断、超时和取消均有反例覆盖。错误文本来自既有自有夹具证据，本轮没有执行 launchctl。

验证：显式使用项目固定 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，`swift test --package-path Packages/ResiduePlatform --filter observedScopedErrorTextRemainsUnknownAndPartial` 1 项通过；同 package 全量 48 项通过。首次未显式固定 Xcode 的命令因当前 CommandLineTools 环境缺少测试构建依赖失败，未计作通过；随后按项目固定 Xcode 重跑成功。`git diff --check` 通过。没有运行服务修改、VM 或 GUI 测试。

复核补充：Label 校验与 collector 对齐，拒绝前导 `-` 和连续 `..`；新增这两类及空值、斜杠、换行的反例。`--filter observedScoped` 两项测试通过，`git diff --check` 通过；此前全量 48 项结果在本次仅收紧 Label 校验之前。

最终复核：`./script/test.sh platform` 全量49项通过（0.127秒），包括收紧后的Label反例；日志 `.local-evidence/runtime-diagnostic-final.log`。
