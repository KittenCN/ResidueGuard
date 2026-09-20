# 只读候选应用归属图

依据 `docs/03-providers-and-detection.md` 3.2/3.11，本轮增加 Core 纯候选图与 Platform 接线。它表达“观察到了哪些可能关联的安装实例及理由”，不表达已验证归属，不改变任何行的 presence、capability、cleanup 或真实影响集合。没有执行软件、扫描其他用户目录或新增系统修改。

## 接口

- `OwnershipApplicationObservation`：扫描代次、volume/file identity、观察路径、Info.plist 声明 bundle ID、签名 identifier/status/Team/DR 元数据、观察时间。签名字段不产生关联边。
- `OwnershipApplicationNode`：本轮展示 id、全部 observations、节点问题。相同扫描代次内相同 volume+file identity 合并物理实例，但保留重复根和别名路径的原观察；不同卷同 inode 不合并。身份未知也保留独立展示节点，不连边。id 不是执行身份证明。
- `CandidateOwnershipEdge`：recordID、applicationNodeID、理由数组。理由仅有 `declaredBundleIdentifier` 和 `lexicalTargetWithinBundle`；都只是候选。
- `OwnershipGraphIssue`：kind、可选 recordID、涉及节点与相关记录。覆盖同 bundle 多实例、同物理实例元数据冲突、提示不一致、重复来源身份、可能共享载荷、覆盖不足、未知代次/身份、解析失败、路径异常与预算限制。
- `CandidateOwnershipGraph`：generation、applications、edges、issues、isPartial。`ownershipVerified` 恒为 false；没有任何 permitsCleanup 或强 owner 构造路径。

`CandidateOwnershipGraphBuilder.build(records:applications:sourceCoverage:generation:limits:)` 不访问文件系统。真实 ScanService 在原有 detached worker 采集所有根完成后构图，`ScanSnapshot.ownershipGraph` 带出结果。既有 `ApplicationInstance` 增加 generation/signingIdentifier，保留过去被丢弃的 signing identifier，并提供 ownershipObservation 转换。原先只用 `Set<bundleID>` 拼接一句声明命中的逻辑被候选边替代。

## 匹配与冲突

声明 bundle ID 精确命中多个安装实例时全部保留；绝不选第一个。程序在观察到的 `.app` 路径内部只产生词法位置提示：逐路径组件匹配，保留大小写，拒绝 `.`/`..`/控制字符和相对路径，不跟随链接，不把 `A.app.other` 认作 `A.app`。同一物理实例的 bundle/signing/Team/DR/status 观察互相冲突时保留原始观察但禁止关联。

声明指向 A、路径提示 B 时保留两种候选并报告不同身份提示；签名 identifier 与 Info.plist identifier 不同时只是未验证元数据差异，不直接判恶意。一条记录声明多个有观察实例的 bundle owner，或多条记录同一程序路径对应不同候选安装实例，报告可能共享载荷。此提示不等于 `sharedComponentActive` 或已证实软件关系。

不按 Label、文件名、相似名称或 same Team 猜 owner。不利用 unverified DR 提高置信度。未知扫描代次、来源身份/实例身份、重复 RecordIdentity、parseWarnings 记录不连边；缺失匹配不表示卸载。来源部分/取消/拒绝/不支持或缺少覆盖数据保持 partial。跨根相同 Label 是否冲突仍需要真实运行域身份，本轮没有按名称推断。

## 有界计算

默认最多 4096 条 source、4096 个应用观察、16384 条边、131072 次候选/路径前缀工作以及 4096 条问题。自定义 limits 也有硬上限：source/app 各20000、边40000、工作262144、问题8192。source coverage 至多检查256项，每条记录至多32个声明和32个target；路径最多4096字节/128组件，身份与签名元数据有字段上限。

使用 bundle ID 和路径索引，避免全部 source×app 笛卡尔积。触发预算会报告 inputLimit + partial，不把未处理部分计为无关联。问题附带节点/记录列表各最多64条，省略明细也报告 inputLimit。原 ScanSnapshot rows/applications 保留采集器的原始列表；图的输入裁剪不能偷偷变成完整系统清单。

## 已执行验证

环境：macOS 27.0 / 26A428 arm64，固定 `/Applications/Xcode.app/Contents/Developer`，Swift 6。执行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePlatform
```

Core 50 项通过（新增10项），Platform 42项通过（新增3项）。新增纯测试覆盖多安装/跨卷inode、重复观察、元数据冲突、弱提示、同Team/Label不关联、路径边界/大小写/遍历、提示冲突/可能共享、未知或旧代次、重复/解析失败来源、覆盖缺口及边/工作/诊断预算。

Platform 使用 `/private/tmp` 随机自有应用/plist fixture：同 bundle ID 的两个目录全部保留并形成两条声明候选；与完全不索引应用的扫描相比，rows.presence 和 capability 相同，未产生红色。重复 root 合并图节点但保留全部观察；失败 plist 行仍为 unknown、不建立边；未知代次 snapshot 仍 partial。测试完成移除仅自身临时目录。未运行 Xcode、GUI、VM 或新增真实宿主扫描。

## 保留限制

当前应用索引仅采集授权顶层 bundle，签名元数据不代表签名有效或可信。Info.plist、目录身份、签名检查不是完整同一时刻的稳定快照；本候选图不能为 inode 重用、并发替换、离线卷状态或来源归属签发证明。合法独立 CLI 仍由既有路径观察表示，不要求有 `.app` owner。UI 应使用“候选关联/可能共享/未验证”措辞，并保留来源覆盖和全部冲突；无候选不展示“已卸载”。App/UI 接线由主任务另行完成。

## 主任务 GUI 接入

“应用关联”页已改为实例节点及候选理由视图，保留多路径观察、声明/签名标识线索、实例限制和图级冲突。它没有选择/确认/执行控件。筛选未命中单独提示，不伪装成没有安装；切入演示/新扫描时清除旧图，防止跨代混用。图边和记录标题按字典索引展示，避免每个实例重新遍历全部边。

Debug-only双实例合成fixture只在同时提供两个显式测试参数时启用，Release不包含入口。定向 `ApplicationAssociationUITests` 两项通过、0失败（26.949秒）：初始未扫描→2实例/2候选/partial/无写控件→无命中过滤，以及切换演示清除旧图。未新增真实宿主扫描。Debug/Release均构建通过；Release双架构严格签名/沙盒验证通过，验证脚本新增检查全部6个GUI注入参数均不在Release二进制中。

随后完整 `./script/test.sh ui`：20项中19通过、1系统picker显式跳过、0失败（251.475秒）。包含全部扫描、预演确认、历史导入、保留规则与应用关联回归；系统picker仍以独立VM实际界面证据说明。
