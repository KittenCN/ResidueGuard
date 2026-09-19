# 09｜交给 Codex 的提示词

## 9.1 首次启动：仅 P0 + P1，只读
下面整段可直接复制。先解压任务包并让 Codex 在该目录工作。

```text
请把当前目录作为 ResidueGuard（macOS 残留管家）的项目根。

先完整读取 AGENTS.md、README.md，以及 docs/00-feasibility.md 到 docs/09-codex-prompts.md。不要根据项目名字把它实现成通用垃圾文件清理器。

本轮只完成 P0 的只读环境核验、能力验证计划，以及 P1 的原生工程和只读 GUI/核心策略。未具备可回滚 macOS 测试环境的系统能力实验要如实标记未验证，不在我的日常系统执行替代实验。

目标是原生 SwiftUI macOS App + 本地 Swift 核心 Package，Swift 6 language mode，建议 minimum macOS 14，按本机兼容的稳定 Xcode 固定工具链。必须先检查实际环境，不能从聊天上下文猜测我的 macOS/Xcode 版本。不要自动升级系统或安装开发工具。

先运行 bash script/preflight.sh。读取本机相关手册与公开 SDK 文档，创建 docs/validation/environment.md、provider-dossier.md、capability-matrix.json；未验证的写能力一律关闭。macOS 27+ 不使用 TCC 数据库直接读取或任何绕过方案。SMAppService 只用于我们自己的服务，不是管理其他 app 的通用接口。

如果当前环境没有 macOS/Xcode，就完成可做的文档核验、纯模型和夹具工作，明确记录阻塞；不能编造构建成功、GUI 可见或权限实验通过。

检查已有 git，创建多文件工程结构。先实现模型、来源覆盖、存在性分类、影响集合和确认策略；用 fixtures/confirmation-cases.json 编写真实测试。实现侧栏、表格、复选框、详情、搜索、筛选、未知/权限不足/不支持状态。演示数据必须醒目标注，不可伪装真实系统结果。

本轮任何按钮都不能真实修改启动项、系统服务或权限；不运行全局重置，不安装提权 helper，不申请无关隐私权限，不删除我的应用文件。清理仅生成 dry-run 计划。

规则：全部实际影响对象为可操作的高可信残留才一次应用内确认；存在仍安装的软件必须两次独立确认；未知/保护/范围不明阻断；系统认证不抵扣产品确认。颜色不是执行权限，按实际影响计算。

有真实 app scheme 后，按可用 build-macos-apps skill 的规范建立 script/build_and_run.sh 和 Codex Run 配置；先读规范，不猜 environment.toml 字段。GUI 以 .app 启动，不直接运行裸 Swift 可执行文件。

每个小任务先测试再实现。最后报告实际修改文件、实际运行命令、构建/测试结果、未验证平台能力、仍被禁用的动作与下一阶段任务，不得把 notRun 算 passed。本轮完成后停止，不自动进入 P2/P3 或打开任何系统写能力。
```

## 9.2 P2：真实只读采集
```text
继续 ResidueGuard，只完成 docs/05-roadmap.md 中的 P2。先检查已有实现与 P1 验收，不重写已经验证的模块。

实现只读文件/ProcessRunner、应用索引、launchd 配置与已验证运行信息、BTM/登录项来源。每个 provider 返回完整覆盖与错误信息，保留未知原始记录。没有访问权限、外置卷离线、Trash、安装更新和共享组件不能标红。Spotlight 未命中不能作为删除证明。

使用安全参数化 Process，不执行被扫描程序或 plist 命令，不挂载离线卷，不读取别的用户私人数据。需要采样原始系统记录时，先说明其隐私内容并保持本地脱敏。仍然不执行任何系统修改，不安装 helper。

提交可重放的判断 fixture、真实读源核对记录和误判测试。最终说明哪些来源只是部分可见，不能只展示“扫描成功”。
```

## 9.3 P3：用户级清理
```text
继续 ResidueGuard，只完成 P3。先读 docs/04-cleanup-security.md 和 docs/06-tests-acceptance.md。必须先通过计划、确认、指纹、备份与恢复测试，然后在可回滚 VM/专用测试账户清理本项目自有测试 LaunchAgent。

不得拿我真实安装的软件做删除实验，不开放 root 或系统级清理。实现不可变计划、真实影响集合、确认失效、一次/两次独立确认、执行前重查、校验备份、精确服务卸载、配置隔离和逐步 journal。不要将文件移除冒充 BTM 历史删除。

任何目标变化/备份失败/卸载失败都停止后续相关修改；无证据的“成功”使用 unverified。恢复配置不得自动重启服务。最后交付实际前后状态与失败注入测试；未有 VM 就保持 mutation 禁用，完成逻辑和夹具部分。
```

## 9.4 P4：特权 helper
```text
只完成 P4，并把安全审查当成发布门槛。先证实目标 SDK 的公开 XPC peer 身份验证方案，不能发明 API、使用私有 KVC 或只信任 PID/路径。SMAppService 仅管理本项目 helper。

IPC 使用有限操作与一次性计划 token，不提供任意 command/path/write/delete 接口。helper 自行核验签名身份、账户、授权、源目录 owner/权限、实际影响、指纹、期限和重放。root 备份只进入 helper 控制的目录。

完成全部 S 系列攻击用例与多用户 scope 测试后，才对通过验证的共享/系统配置动作开放能力。未知或 MDM/系统保护对象锁定。没有可回滚环境时不在我的主系统安装或测试 helper。提交自安装、批准、升级和自卸载证据。
```

## 9.5 P5：权限模块
```text
只完成 P5。复核官方当前文档及 P0 实测矩阵；现代权限页允许 guidedOnly，但不能以空列表隐藏不可读取。macOS 27+ 不直读 TCC。旧版只读 adapter 必须按 schema/权限/profile 受控启用。

tccutil 仅对已证实的 service、client 和 scope 做精确重置；测试已安装/真正删除 app、路径型 client 与自动化 caller-target 粒度。找不到 bundle 或能力不支持时停止，绝不扩大全量 reset。重置后不可验证 UI 历史消失时准确报告。

本地网络/定位不要套用猜测的 TCC token。不实现自动批准权限、复制数据库恢复授权或自动操作系统设置来伪装 API。每个开放修改能力附真实平台证据，其他类别提供用户看得懂的手动步骤。
```

## 9.6 P6：发布审查
```text
只完成 P6。按测试矩阵复核 UI、性能、日志隐私、导出安全、OS 降级、签名、公证和自身 helper 移除。把全部开放 mutation 与其真实证据逐一对应；没有证据就禁用，不靠演示数据验收。

输出支持清单、已知限制、用户操作手册、恢复说明和实际测试报告。不得宣称清理全部权限、100% 不误删、自动恢复授权或固定性能提升。不要提交任何证书私钥、真实权限数据库或用户软件完整清单到 git。
```

## 9.7 中途接续模板
```text
先读取 AGENTS.md 与相关规格，再查看 git diff/status 和 docs/validation 中上次真实结果。本轮任务是：[填一个明确 ticket，例如 P2-04]。
保留既有约束和未验证能力的禁用状态，不为通过测试更改安全规则。完成后报告：改了什么、实跑了什么、哪些没跑、下一步具体阻塞；不要自动跨阶段启用系统写操作。
```
