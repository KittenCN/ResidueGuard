# 固定 VM 实验持久日志接入

环境：macOS 27.0 / 26A428、Xcode 27 / 27A266a、Swift 6。仅自有 ISO01 专用 VM 夹具，第三方清理 gate 保持关闭；不需要 Developer ID。

## 实现

新增独立实验日志，固定 profile 为 `owned-iso01-observation-isolate-restore-v1`。它与生产/合成事务 journal 的 schema、nonce 和授权类型分开，不生成 `VerifiedTransactionPlan`。记录固定源与程序完整指纹、源/隔离目录身份、UID/build、120秒实验期限及备份 root/ID/content/metadata/manifest 绑定。没有任意命令执行接口。

实验顺序为备份核验、持久 prepare、重新核验程序/运行态、隔离、观察并持久 result、只读恢复检查、再次 prepare/新鲜核验、预先计划的恢复、观察并持久 result。恢复不是错误后的自动补偿。结果写入失败后不继续下一动作；prepared 而无 result 明确为结果未知。过期阻止下一 prepare，仍允许保存已发生的结果。

程序用同一打开 fd 在签名前后读取有界内容并核对完整指纹，再验证目录命名身份。严格只读 journal 重开不创建文件、不变更 journal mode；历史数据和内容校验都不构成来源真实性或恢复授权。

## 实际结果

- `swift test --package-path Packages/ResidueBackup --filter OwnedFixtureScenarioTests`：最终14 项通过，新增准备失败、结果失败、真实文件动作顺序、动作后未知运行态留证测试。
- 固定 Xcode 下 Release `ResidueOwnedFixtureVMProbe` 构建成功；宿主零参数退出77，额外参数退出64，均未运行源修改。
- 专用 VM v5及最终v7 探针实际退出0：备份/隔离/检查/恢复完成；前后备份审计证据一致；两步日志已准备、记录并通过只读第二连接读回。原源文件恢复，服务仍 registeredNotRunning，注册修改次数为0。
- 本地原始结果为 `.local-evidence/vm-transfer/ownedprobe-v7-result.txt`，不提交个人路径及原始ID。

## 限制

往返探针的第二连接读回发生在同一进程。随后独立启动的只读审计探针也已实测exit0，读取1条实验/2个步骤，源matchesHistory、隔离absent；5个早期实验目录没有journal，明确计数，失败/拒绝根为0。这证明跨进程历史及当前文件观察，不等于重启后恢复执行。后续新实验日志已增加有界runtime来源字段，旧日志继续明确缺失（见下）。源检查与rename间竞争仍存在，固定自有夹具实验不能推广为第三方清理安全。实验结果观察不签名，不把可改写历史当新的执行凭据。root helper、系统级来源修改及生产GUI写入均未启用。

最终Backup54、Quarantine51项通过（真实文件加journal集成7项包含在后者）；Persistence37项通过，含18个真实进程SIGKILL场景。

审查修复：持久prepare后重新观察运行态，再同步核验程序身份、期限与取消，最后进入文件操作；不再在最后程序核验后await。新鲜身份/运行态失败归beforeIsolation/Restore，日志写入失败保留独立阶段。prepare后明确未执行但停止时仍保留pending，这是保守结果未知，不伪装已完成或自动重试。

客体终端最初两次命令输入被终端解析成ash/ubash并报command not found，未执行探针。之后完整命令实际成功；没有把输入尝试计为验收。

## 后续：运行态来源绑定

新增可选历史runtimeEvidence，保存UUID代次、provider/scope/Label、build/parserProfile、观察时间、stdout摘要、退出/失败/截断与coverage/state。不存原始输出。已知registeredNotRunning必须符合固定身份和成功完整采集；unknown失败保留，不能放行。记录时间只与对应prepare/result比较，不把旧历史看成当前观察；旧缺失字段保持nil与原canonical读兼容。

Platform47项、Persistence41项（18个进程崩溃场景）、Backup54项、Quarantine53项通过；新增bridge2项检验成功与失败/截断信息保真。bridge测试初次编译因跨模块internal诊断fixture构造不可访问而失败，改测试专用@testable导入后通过，没有放宽public API。

Release重新构建后VM v8实际退出0，两步runtimeEvidence均已记录。随后独立reader v2退出0，读取3条实验共6步；两条旧记录的runtimeEvidenceSteps为0，新记录为2，三个源matchesHistory、隔离absent。5个无journal早期目录仍单独计数，失败/拒绝根为0。reader明确runtimeInspected=false，表示它没有重新观察运行态，历史字段不能替代当前状态。
