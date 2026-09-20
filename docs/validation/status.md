# 项目当前状态

更新：2026-09-20。已从 P0/P1 扩展到受限 P2 只读扫描、P3/P4 纯策略、P5 权限引导与 P6 报告/发布准备。**全项目尚未完成，所有真实系统修改仍关闭。**

- 原生 SwiftUI App、明确合成演示与 dry-run 已建立；真实扫描仅声明范围内只读，失败和未覆盖来源可见。
- Core 30、Security 11、Platform 28 项测试通过（本轮增加路径/schema/token 回归）。静态签名读取只提供 metadata，不证明信任有效。
- 最终完整 11 项 GUI 回归通过（94.763 秒，0 失败）；报告预览首次辅助功能断言失败的原因、修正与针对性复测保留在综合报告。
- P3/P4 事务、恢复和 helper 请求策略有合成测试，但真实 driver、持久化 journal、XPC 传输和 helper 生命周期尚未实现/验证。
- P5 提供 19 类权限注册表与降级引导；P6 提供默认脱敏 JSON/CSV 预览；本地预览打包、正常 `.app` 启动通过；发布门禁 exit 2 拒绝非 Developer ID、无 Hardened Runtime 且含调试 entitlement 的包，正式分发未通过。
- 隔离清理、实际权限重置、helper 攻击测试、跨 OS/Intel、完整可访问性、Developer ID/公证与正式发布均未通过。

最新命令与结果：[本轮综合报告](final-development-results-2026-09-20.md)。阶段缺口：[项目进度](project-progress.md)。隔离/签名要求：[实验入场条件](../isolated-validation.md)。旧报告只记录其对应轮次，不覆盖当前未验证项。

2026-09-20 VM 接续：已识别 VirtualBuddy 客体、正常关机建立 APFS 回滚副本、配置专用交换目录并准备只在 VM 执行的自有 Agent 夹具。客体重启后等待本地登录；尚未实跑 ISO-01/04。最新证据见 [VM 接续报告](vm-continuation-2026-09-20.md)。
