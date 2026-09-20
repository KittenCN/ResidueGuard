# 直接目标近期消失：会话内只读保护

2026-09-20。修复已观察直接可执行文件从存在变为 ENOENT 时仍立即落入一般疑似的问题。不是更新检测器，不推测有 updater，也不改变任何执行 gate。

## 生产接入

`WorkspaceScanner.live` 每次创建新的 `ScanService`，所以历史不能仅放采集 actor 内。新增 Sendable 值型 `RecentTargetDisappearanceTracker` 由长期 `WorkspaceStore` 持有，在现有 detached 比较任务中复制并应用；返回后经过 requestedGeneration 检查，只有未取消的当前请求才提交新历史。扫描开始清空显示不清空历史，演示不输入历史。无需复用采集 actor，也不在 MainActor 遍历 10k 行。

`ScanRow` 新增 typed directTargetObservation，默认 unverified；只有真实文件描述符检查得到可执行普通文件或直接路径 ENOENT 才分别填 executablePresent/missing。分类比较不用展示字符串猜测。

历史键包含来源 RecordIdentity（provider/scope/native identity）、完整来源 SHA256、精确目标、来源根、OS build。只接受唯一来源、无解析警告、一个精确目标、相同 generation 的唯一 root/scope coverage。只有该配置根 complete 且无 errors/skippedAreas 才更新；applications.index 的 partial 不妨碍直接目标证据。取消、不完整、未知 build/hash、身份或边界冲突不能建立或释放历史。

首次缺失保持 suspectedOrphan。曾直接存在的同键目标后来 missing，presence 为 unknown，中文解释保持到同键直接存在；不随时间退回疑似。来源变化、目标变化、scope/build变化不交叉关联。未知观察不会释放已经记录的保护。能力和候选图原样保留；应用是否卸载、未来是否重建都不作推断。

## 有界性与限制

coverage 预索引，正常比较为线性遍历；最多 20,000 行、128 coverage、20,000 历史键。历史满后不淘汰旧保护，不录入新键。输入超限不更新历史，保留所有行但把疑似统一投影为 unknown，并说明限额；这一步仍需线性输出投影，不构造额外比较索引。

这是内存会话历史，退出工作区/应用后不持久化。generation 需有效 UUID 且不等于上次接受代次，observedAt 严格晚于上次接受日期；系统时钟回退时暂停新增/清除历史，直到观测日期超过上次值，已有消失保护保留。工作区请求 generation 门禁进一步阻止异步旧请求覆盖当前状态。这里没有引入时钟驱动的保护到期。

## 验证

macOS 27.0 / 26A428；固定 Xcode 27.0 / 27A266a。

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePlatform`：56 项通过。新增 6 项覆盖首次缺失、持续缺失、恢复、hash/target/scope/build隔离、取消/不完整/旧日期、未知观察、容量、重复边界/记录、超限保守投影。

临时文件集成测试使用三个独立 `ScanService` 实例和一个持续 tracker，实际生成自有不可执行内容文件但设置执行位、删除再重建，只检查文件属性，绝不执行内容；验证 present→unknown→present，来源行始终存在，能力 readOnly。其余为纯模型注入。没有运行 launchctl、真实 VM、签名信任验证或 GUI。本轮 WorkspaceStore 接入由主任务后续统一构建验收；包测试不替代 app 编译/界面测试。

主任务集成验收：`./script/build_and_run.sh --release-build-only` 成功，WorkspaceStore接入实际编译通过；arm64/x86_64严格签名、只读沙盒、无debugger entitlement检查通过。日志 `.local-evidence/disappearance-release-build.log`。未运行本项GUI或VM，不把编译通过代替显示交互验收。
