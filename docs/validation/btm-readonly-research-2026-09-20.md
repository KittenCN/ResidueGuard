# BTM / 登录项只读来源研究 — 2026-09-20

最终结果：专用VM两次非root只读调用（5秒、30秒）均超时且无输出，根因未知；Platform 46项测试通过。未获得可解析样本，产品仍unsupported。下文按研究、实现、实测记录，末节为最终结论。

## 研究阶段结论与证据等级

研究开始时，macOS 27.0 / 26A428 的非 root `sfltool dumpbtm` 权限、输出作用域、输出大小和格式仍为 **unverified / notRun**。官方介绍该诊断命令，不等于已验证此 build 的普通用户采集能力。产品 BackgroundTaskProvider / LoginItemsProvider 继续 unsupported；没有新增 parser、命令入口、授权或写能力。

本轮读取 `docs/03-providers-and-detection.md` 3.5–3.6、P0 `environment.md` / `provider-dossier.md`、当前 capability matrix、本机 man page 和公开 SDK header，以及 Apple 文档。没有运行宿主 dumpbtm、archive、VM 命令、私有数据库读取、安装、注册、卸载或权限变更；没有运行测试，因为未改实现。

| 来源 | 本轮确认 | 不能推导 |
|---|---|---|
| [Apple Platform Deployment](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web) | Apple 将 dumpbtm 列为登录项/后台项状态诊断工具 | 非 root 在 26A428 必然可用、仅当前 UID、稳定机器协议、全量覆盖或逐项删除 |
| 本机 `MANPAGER=cat man sfltool \| col -b` | 当前手册只描述 SharedFileList 的 archive / archive -z，未列 dumpbtm | 不据旧手册否定官方诊断，也不臆造 UID 参数 |
| Xcode 27 SDK `ServiceManagement.framework/Headers/SMAppService.h` | macOS 13+ 提供调用应用自身 bundle 内 login item、agent、daemon 的服务对象与 status；legacy status 用于已知自身服务 plist | 任意第三方全应用枚举或卸载 |
| P0 档案与 capability matrix | 没有 dumpbtm 样本，BTM/LoginItems documentaryOnly | 不能将之前 launchd/VM 验收挪作 BTM 验收 |

SDK 读取根为 `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`。`statusForLegacyPlist(at:)` 虽有公开路径参数，但文档定位为应用检查自己的 legacy helper；不能用于代替第三方完整来源。普通 CLI 实验即使成功，也不证明当前沙箱 GUI 可以调用该工具或具有相同覆盖。

## 作用域门槛

没有查到已验证的来源侧 UID 过滤参数；不得编造 `--uid` 或 `-u`。docs/03 要求多用户输出按授权范围过滤，但过滤只能限制留存和使用，不能证明底层命令未读取其他用户私有数据。若工具默认输出多用户且没有公开、可验证的当前用户采集机制，不能直接接入日常主机扫描。先在仅含测试账户/测试软件的可丢弃 VM 探索；若范围门槛无法解决，产品维持 unsupported / 手动引导，不能改用 root 或私有存储绕过。

未来 parser 仅将已验证语法中的精确数值 UID 与调用进程实际 UID 匹配。缺失、重复冲突、未知或模糊范围拒绝关联；root、负数或汇总 UID 不映射为当前用户。用户名、路径包含 HOME、App ID/Team ID 均不替代 UID provenance。跨范围父子关系保留“范围外/未知”事实，不拉入隐藏 owner，也不将另一范围缺失当作删除。

## 最小 VM 采样建议（尚未执行）

仅在下一次单独有界 VM 任务中执行。第一阶段无需新建 fixture、启动被检查 app、注册服务或修改系统设置；观察现有自有 fixture 即可，未见它也不说明不存在。

1. 用固定 `/usr/sbin/sysctl -n hw.model`、`/usr/bin/id -u`、`/usr/bin/sw_vers` 验证 VirtualMac*、非 root、27.0 / 26A428。记录管理员组成员与非管理员测试是否分别验证；“非 root”不等于“非管理员账户”。
2. 由有界诊断 runner 直接启动唯一采样命令 `/usr/bin/sfltool`，参数数组 `["dumpbtm"]`，不经过 shell，不加 sudo，不猜范围参数。
3. 建议初始预算：5 秒、stdout 1 MiB、stderr 16 KiB、单行 16 KiB、记录 4096 条、父子深度 16。此为待验证保守预算，不是系统输出保证。并行排空两管道，超量/超时/取消仅终止并回收自己创建的子进程；独立记录退出码、字节数、截断、超时和取消。不要以 `head` 管道伪装完整结果，也不要无界重定向原始输出。
4. 原始 VM 输出只在受限本地证据区短期保存，不进 git/普通日志；报告仅计数、状态、范围结论。制作 fixture 前移除用户名、真实路径、软件清单及非测试对象标识，保留语法与一致的替代 ID/父子引用。只把自有 fixture 的脱敏片段带入测试。

权限拒绝、命令不支持、空输出、非零退出、未知 UID/格式分别记录；不自动提权或请求 Full Disk Access。需要验证非管理员账户时应单独安排，不能仅凭当前 UID 非零宣称通过。当前没有为上述步骤新增脚本或 runner API。

## 未来只读解析契约

- Profile 必须绑定实际 OS/build、工具及 parser 版本与脱敏样本。未知 build、未知结构、重复原生 ID 冲突、缺少 scope 或不完整结束均 fail closed；保留有界未知摘要并降低 coverage，不返回成功空列表。
- 保留原生记录 ID、原始类型/状态、来源、父子关系、观察代次和范围。未知数值或位标志不推断“启用”“允许”“运行”；注册可见、当前运行、文件存在和卸载判断分别建模。
- 即便已知片段可展示，超时/截断/未知部分使来源 partial；只有已验证结构完整与范围成立时才能说 completeWithinDeclaredScope，不能称所有登录项完整。
- BTM 中声明 App ID/Team ID 只是候选证据，不成为强 owner；与 launchd 的 describesSameArtifact 必须核对当前 scope/来源身份，不能只按 Label 或 bundle ID 合并。
- LoginItemsProvider 只投影真实测试过的登录项类型，保留同一来源身份及 provenance。旧式登录项/API/Automation 是独立验证范围，未实现部分明确 unsupported。
- 所有修改 capability 保持 false；没有逐项历史删除入口时仅 guidedOnly，不实现全局 reset，不读取/写入 BTM 私有存储。

真正实现前至少需要测试：当前 UID/其他 UID/未知范围、重复和缺失 scope、跨用户父子引用、重复 ID、未知类型/字段、截断在行中或记录间、空/非零退出、取消/超时/超限、未知 build、无候选不等于卸载、登录项投影不重复。成功命令测试不能替代这些边界。

## 下一步决策

先获取一次有界非 root VM 诊断，确定是否存在可满足产品用户范围约束的公开来源；如不存在，继续明确显示不可枚举，而不是开发一个先越范围采集再过滤的宿主 provider。本研究不改变项目当前 capability matrix 的 unverified 状态。

## 后续实现：独立 VM 实验探针

研究完成后按主任务指示新增 `ResidueBTMExperiment` 独立零参数 CLI；上述研究期“未新增代码”的记录仍指研究阶段。package-only `BTMExperiment` 在执行工具前检查 VirtualMac*、非 root、精确 27.0.0 / 26A428，拒绝所有参数。固定 `/usr/bin/sfltool` 还必须为 root 拥有、非组/其他用户可写的普通可执行文件，不接受符号链接。调用参数固定为 dumpbtm；没有新增 public ReadOnlyDiagnostic 请求。

复用诊断 capture，增加独立 stdout 1 MiB / stderr 16 KiB 上限与 5 秒超时。JSON 保留原文、退出码、failure、截断与拒绝原因，并始终标记 experimentOnly / scopeUnverified / mutationAvailable=false。不解析记录，不返回产品清单。JSON 转义及 UTF-8 替换后的序列化大小可能大于原始捕获字节上限；原始管道内存仍有界。原文仅适合 VM 本地私有证据，不提交 git，不作为正常产品日志。

实际验证：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePlatform` 45 项通过；新增三项测试覆盖门禁不调用 capture、失败保真及两流独立限额。增加工具属性检查后重跑 targeted 三项通过。release product 构建通过。宿主 release 零参数运行退出 77 / nonrootVMRequired，传 --help 退出 77 / zeroArgumentsRequired，两者 stdout/stderr 诊断原文均为空，未运行宿主 sfltool。

构建命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path Packages/ResiduePlatform -c release --product ResidueBTMExperiment`。产物为 `Packages/ResiduePlatform/.build/out/Products/Release/ResidueBTMExperiment`。纯 CLI 可复制到专用 VM 后直接运行，不是 GUI .app；VM 实际采样仍待主任务执行。非 root 门禁不声称账户非管理员。

## VM 首次结果与一次复测预算

主任务在专用 VM 的普通登录账户运行 v1，未提权。本轮读取其本地 JSON 证据：failure=timedOut，exitCode=15，stdout/stderr 均空，outputTruncated=false。超时是失败，不是“零条记录”；没有输出不能确定权限原因、BTM 状态或工具内部等待原因。没有获得可解析样本，scope 仍未验证。

按主任务指示，将探针固定超时由 5 秒延长至 30 秒，仅用于再一次有界 VM 复测，输出限额和其他门禁不变。JSON 新增 timeoutSeconds、stdoutByteLimit、stderrByteLimit 与 elapsedSeconds；elapsed 使用单调时钟测量门禁通过后的 capture（含固定工具检查及进程收尾），可能略超过命令超时预算。门禁拒绝时 elapsed 为 0。没有新增参数、产品入口或自动重试。

复测若仍无输出或超时，应记录“此环境机制尚未验证，原因未知”，停止反复尝试；不提权、不重置、不读私库。新增 elapsed 测试与原门禁/限额/失败保真测试共 4 项 targeted 通过；release 重建通过。30 秒 VM 实跑结果待主任务补充。

## VM 最终结果与公开资料复核

已读取主任务第二次 VM 结果：timeoutSeconds=30，elapsedSeconds=30.013807125000312，exitCode=15，failure=timedOut，stdout/stderr 均为空，outputTruncated=false。与首次 5 秒结果一致地没有获得样本；exitCode 15 出现在 runner 超时终止之后，不能当作工具自行诊断的权限错误。两次均在专用普通登录账户、不提权执行。到此停止采样重试；产品仍 unsupported，不是 empty。

按照 AGENTS 不明机制先检索公开资料，本轮检索 Apple Developer Forums 的 sfltool/dumpbtm + hang、sudo、unprivileged、macOS 27，以及官方支持与发布说明。结果区分如下：

- [Apple 部署指南](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web) 证明诊断命令存在，未说明本次零输出超时的根因或必需 root。
- [Apple DTS 回复：UID -2](https://developer.apple.com/forums/thread/768241) 说明该 UID 对应 nobody；发帖者展示的是 sudo 输出。此证据支持不把未知/其他 UID 当当前用户，但不证明 sudo 为命令的必要条件，也不是 26A428 的样本。
- [SMAppService sample discussion](https://developer.apple.com/forums/thread/799910) 涉及 macOS 13 上服务注册、签名与 XPC 等待问题；虽然含 dumpbtm 输出，但并非 dumpbtm 在 macOS 27 非 root 超时的复现，不能套用其签名/注册讨论解释本次失败。
- 已查阅 [macOS 27 官方 release notes JSON](https://developer.apple.com/tutorials/data/documentation/macos-release-notes/macos-27-release-notes.json)，本轮没有找到直接解释 dumpbtm 非 root 零输出超时的条目。搜索未命中不证明 Apple 没有相关内部问题记录。

结论：**根因未知**。权限要求、系统服务等待、特定 build 缺陷等均未被证据证实，不归因于必须 root、数据库损坏或账户配置，不开展提权/重置/私库实验。若未来需要继续，应先取得可复现的官方机制说明或新的独立问题证据；当前不扩大接口。

最终完整验证：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePlatform` 46 项通过（macOS 27.0 / 26A428，固定 Xcode 27）。只读测试不替代 BTM OS 来源验收；本次没有新增宿主/VM dump 调用。
