# 扫描提示可见性与布局回归

VM 的较小窗口中，原底部提示可能在可见区域之外。现将状态提示移到扫描按钮附近，窗口默认高度为660。

最初使用随内容高度增长的 Text 在扫描后切换表格时真实触发 AppKit/SwiftUI 约束循环并 SIGABRT（本地崩溃日志含 NSWindow _postWindowNeedsUpdateConstraints 与 NSHostingView transaction）。改为固定40点高的可滚动提示区，显式 accessibilityLabel/value，避免反复改变 split view 子区域最小尺寸。

首次11项 UI 回归3失败（1个label/value断言、2个约束崩溃）；修复后3项针对性回归通过，随后完整16项中15通过/1系统picker跳过/0失败。提示断言等待实际value更新，未用sleep遮盖失败。日志仅留忽略目录。

环境 macOS27/26A428、Xcode27/27A266a。后续VM Release运行时，扫描按钮附近的状态提示实际可见；已有保存窗口尺寸仍会被系统恢复，没有据此声称全尺寸/最小窗口与可访问性全部通过。
