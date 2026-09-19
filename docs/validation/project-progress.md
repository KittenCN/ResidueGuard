# 全项目阶段进度与放行门槛

检查日期：2026-09-20。此页是阶段验收索引，不替代每次构建/测试的原始结果。`passed` 仅用于已实际运行并通过的检查；代码存在、计划已写、mock 测试通过均不等于系统集成通过。历史 P0/P1 任务的边界说明仍保留在原报告中；新一轮跨阶段开发允许实现后续模块，但不会自行放开真实系统写能力。

## 已核对的基线

已阅读 [P0/P1 实测报告](test-results-2026-09-20.md)：10 个核心测试（内含 24 条确认夹具）、6 个 XCUITest、干净 Debug 构建、普通 `.app` 启动及本地 ad-hoc 签名校验通过。这是前一轮报告中的实际结果，本次阶段盘点没有重复运行这些测试。真实能力 profile 见 [capability-matrix.json](capability-matrix.json)，当前无已验证写 profile。

| 阶段 | 可确认的基线 | 剩余必需验收 | 放行状态 |
|---|---|---|---|
| P0 | 环境/手册/SDK 边界和隔离实验计划已记录 | 真实 provider 输出和身份样本、隔离 app、权限与 helper 平台实验 | 部分完成；写能力 `notRun` |
| P1 | 原生 App、独立核心、合成演示与 dry-run；历史报告中构建/核心/UI 测试通过 | 浅深色、高对比度、VoiceOver、长文案/最小窗口等人工与辅助技术验收 | 开发基线可用；未测试项不计通过 |
| P2 | 新任务正在实现真实只读来源；不得提前视为通过 | 安全 I/O/子进程限制、索引/归属、逐源 coverage、真实脱敏样本逐行核对、取消/代次/差异、误判矩阵 I01–I18/D01–D04/D13–D16 | 以本轮具体结果更新；整阶段尚未通过 |
| P3 | P1 已有计划/确认纯逻辑，不是清理执行授权 | 备份/manifest/journal/恢复、竞争与故障注入、VM 自有用户 Agent 精确清理 M01–M12、后台历史独立验证 | 主机写能力关闭；平台实验 `notRun` |
| P4 | SDK 公开身份校验接口已确认声明存在 | 自身 helper 签名生命周期、XPC 独立身份、一次性 token、目录和源身份安全、多用户及 S01–S11/S14 攻击矩阵 | helper 安装/调用不开放；平台实验 `notRun` |
| P5 | 现代权限页限制与手动路径；macOS 27+ 无 TCC 直读 | 分类 registry/profile、历史快照只读、各精确 reset 粒度/失败/后置验证 D05–D12；旧版 adapter 仅合格 profile 可选 | 现代引导可用；真实 reset 和旧版读库不开放 |
| P6 | 现有测试脚本与本地 Debug 工程 | 10,000 行性能、无泄漏导出、日志/忽略策略、可访问性、多 OS/build、Developer ID/Hardened Runtime、公证、干净安装/升级/自卸载、用户文档 | 尚未发布验收，不可宣称正式完整版本 |

## 本轮可并行完成的纯逻辑工作

以下是有界实现建议；是否已实现、通过哪些测试必须另记实际结果，不能因本清单存在而勾选完成。

1. **P3 事务决策与 journal 状态机**：输入为不可变计划、独立确认凭据、授权结果、最新身份观察及已验证备份证据；输出有限步骤或阻断理由。先持久化准备状态再允许动作；备份失败、journal 失败、指纹变动、bootout 未知/失败均停止依赖链。分别输出文件、runtime、registration、permission 结果，不使用一个 `success` 布尔值覆盖差异。mock 依赖用于验证调用顺序与故障分支，不接入主机操作。
2. **P3 恢复规划和崩溃检查**：manifest/version/hash/身份/元数据必须可核验；原路径已占用、已安装新版本、备份被篡改则拒绝。未完成 journal 只产生观察/恢复计划，不自动继续删除。恢复不包含自动启动或旧权限授予；M02/M03/M06–M11 做可重复注入测试。
3. **P4 狭窄协议和 token 策略**：定义版本化 `queryStatus / prepareKnownSourcePlan / executePreparedToken / queryOutcome / prepareKnownBackupRecovery` 类型；没有任意 command/path/write/delete。token 绑定客户端身份、用户/scope、policy、digest、nonce、expiry，重放返回已记录结果或拒绝。纯逻辑不能证明 XPC 身份真实性，连接身份最终必须来自经验证的公开 API。
4. **P5 精确权限计划门禁**：类别/操作/OS-build 的独立能力映射，未知 service/client/scope 默认 guidedOnly；卸载 bundle 失败不扩大全量 reset；caller-target 粒度变粗使原计划失效；后置不可观测保持 unverified。macOS 27+ 直读保持禁止。
5. **P6 脱敏和导出**：路径/用户名/权限记录默认不进入普通日志；CSV 公式前缀和引号换行安全、JSON 只作为数据；导出不可被当执行计划导入。10,000 条合成记录测试测量实际延迟，不写未测性能承诺。

## 不能靠纯逻辑放行的门槛

当前窄范围隔离工具探测未发现常见 VM 应用/CLI；本机可用代码签名 identity 计数为 0。详见 [隔离测试准备与证据规范](../isolated-validation.md)。这些结果不代表全机绝无 VM，也不代表无法使用 ad-hoc 本地 Debug；它们不足以批准 P3/P4 的隔离平台测试或 P6 分发。

- 不以创建协议、编写 helper 源码或 mock 拒绝测试冒充已通过签名 XPC 安全测试。
- 不以临时目录文件实验冒充 launchd/BTM/TCC 的实际行为验证。
- 不以 deployment target 14 或 arm64 本机通过冒充 macOS 14/15/26 和 Intel 兼容。
- 不以 codesign ad-hoc 校验冒充 Developer ID、公证或 helper 稳定身份。
- 不安装或启动 VM，不自动创建测试账户，不代替用户接受协议，不在日常主机做真实清理。

## 全项目完成的定义

所有已开放 provider/动作有逐 OS/build 真实证据；未知能力保持只读/引导；P3/P4 安全用例无未解决的错误删除或越权路径；发布与卸载验收完成。范围内允许以明确的 guidedOnly 交付平台本就不支持的权限类别，但不能把尚未开发、未测试的必需模块重命名为“平台限制”来宣布全部完成。
