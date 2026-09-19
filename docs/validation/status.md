# P0 / P1 状态

范围：只读环境核验、能力实验计划、原生 SwiftUI 工程、独立 Swift 6 核心与合成演示。实际系统采集属于 P2，本轮不进入。系统修改属于后续安全门槛，本轮没有执行器。

P0 证据见 [environment.md](environment.md)、[provider-dossier.md](provider-dossier.md)、[capability-matrix.json](capability-matrix.json)。P1 实测结果和未验证项见 [test-results-2026-09-20.md](test-results-2026-09-20.md)。

没有可回滚隔离环境的系统能力实验均为 `notRun`。所有真实 mutation 能力关闭。演示数据的模拟可操作性只用于 dry-run 确认策略，不会开放主机上的真实操作。

下一阶段必须由新的明确任务启动；本轮结束不自动进入 P2/P3。优先补齐 P1 尚未通过的验收，再决定是否开始真实只读采集。

## 本轮实际交付

P0 环境与能力实验计划已交付，平台集成实验仍 notRun。P1 原生 Xcode App、独立核心、只读 GUI、显式合成演示与 dry-run 确认已实现。干净 Debug 构建、正常 .app 启动、10 个核心测试（含 24 条确认 fixture）与 6 个 UI 测试通过。额外人工窗口检查因 Computer Use 通道不可用未执行；浅深色/高对比度/VoiceOver、最低系统版本与发布签名仍未验证。不能据此宣称 P0 全部能力或全部 P1 外观/可访问性验收通过。
