# 只读索引与候选图误判边界补测

2026-09-20；对应 docs/06 I01/I02/I03/I12 的已实现部分，不宣称这些完整验收项全部通过。依据 docs/03 的安装实例保留与证据流程，候选关联不能提升为已验证归属或清理授权。

| 场景 | 本轮证据 | 保留的边界 |
| --- | --- | --- |
| I01 移动路径 | 临时自有 app 目录在两个明确索引根之间实际 rename；相同 inode/device、新路径、新扫描代次，声明 ID 候选仍存在，未判高可信残留 | 仅 Info.plist 的未签名目录，不是有效签名应用迁移验收；候选只由声明 ID 建立 |
| I02 同 ID 多副本 | 既有 Platform 两个真实临时目录测试纳入全量回归；Core 新测试保留两个同声明 ID、同末尾目录名、不同物理身份实例 | 未验证替代副本的签名有效性；不按声明 ID 合并实例或宣称强归属 |
| I03 同名不同签名 | 新 Core 纯模型测试使用不同 team/signingIdentifier 提示，保留实例与冲突，只有声明 ID 候选；移除声明 ID 后没有边 | 签名值是合成未验证提示，不是真实签名验证；本轮没有创建证书、签名或调用信任验证 |
| I12 暂时不可见 | 临时目录移出索引根后扫描，再移回；间隙图没有旧实例或旧边、覆盖仍 partial、ownershipVerified false；返回后只含新代次观察 | 没有观察真实 updater，也没有实现更新检测/延迟复核；原 Program ENOENT 仍可能是 suspectedOrphan，绝非 highConfidenceOrphan，不应把本测试称为完整 I12 unknown 分类验收 |

所有阶段源行能力仍 readOnly。本轮只新增测试，没有改变分类规则、候选图算法或生产能力。临时目录使用随机 UUID，测试后仅删除自己的目录；未执行其中任何载荷。ScanService 自带的 CodeIdentityInspector 对这些临时目录仅采集已有只读元数据，不构成签名信任验收。没有 launchctl 调用、源清理、真实 VM 或 GUI 测试。

验证环境：macOS 27.0 / 26A428，Xcode 27.0 / 27A266a，显式固定 DEVELOPER_DIR。

- `swift test --package-path Packages/ResiduePlatform --filter indexTracksMovedInstallation`：1 项通过。
- `swift test --package-path Packages/ResidueCore --filter ownershipSameDisplayName`：1 项通过。
- Core 全量：60 项通过。
- Platform 全量：50 项通过。
- `git diff --check`：通过。

后续边界：真实有效签名的替代安装实例和真正更新窗口，需要专用自有 VM 夹具及新的验收证据；不从本次临时文件/纯模型通过推导这些能力已具备。

复核后强化四个扫描阶段：都显式断言来源行恰为 1，再用 `#require` 解包后检查 presence/capability，避免行丢失时 optional 比较错误通过。强化后该专项测试再次通过；前述全量在此测试断言强化之前通过。
