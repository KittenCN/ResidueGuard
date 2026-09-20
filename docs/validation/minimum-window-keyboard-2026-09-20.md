# 最小窗口下的双确认与键盘取消

2026-09-20；macOS 27.0 / 26A428、Xcode 27.0 / 27A266a、arm64。
本轮使用 build-macos-apps:test-triage 的定向测试流程。读取 AGENTS 与既有确认测试后，
确认已有双确认/鼠标取消，但没有最小窗口 + Escape 的组合回归。

新增 `Tests/UI/MinimumWindowUITests.swift` 并加入已有 UI test target；无产品代码改动。
测试启动默认只读 App，仅载入内置合成演示，不读取主机来源、不执行系统动作。
通过实际窗口 frame（拒绝无限值/空frame）的右下角坐标拖动缩小；再尝试缩小一次，
确认系统夹持后的尺寸没有进一步改变。实际观察外部窗口 **980 × 692 points**，
与产品内容最小尺寸980 × 640及系统窗口装饰相容。

在此窗口中验证：

- 选择仍安装的合成记录；打开dry-run，范围批准和第一次确认按钮可达。
- 第二次确认最初禁用，风险短语可输入；输入后第二确认启用且可达。
- 第二确认启用后发送键盘Escape：对话框关闭，没有出现“预演确认流程完成”。
- 重新打开必须重新批准影响范围，没有保留上一轮第二确认授权；最后正常取消。

实际命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ResidueGuard.xcodeproj -scheme ResidueGuard -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build-xcode \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -only-testing:ResidueGuardUITests/MinimumWindowUITests/testMinimumWindowDoubleConfirmationRemainsReachableAndEscapeCancels test
```

结果：**1 test passed / 0 failed / 0 skipped，23.450秒，TEST SUCCEEDED**。
日志 `/private/tmp/minimum-window-ui.log`；没有重跑全量UI。
本轮没有变更系统设置、启用VoiceOver、改变颜色模式或修改生产UI；因此不算完整可访问性、
高对比度、长文案或所有窗口/显示器组合验收。测试结束退出自己的App，没有提交桌面截图。

审查后修正测试的状态恢复假设：启动时本就最小也应通过，因此允许缩窗前后宽度相等，
并同时断言宽度980–982、外框高度640–720（包含窗口装饰），以及再次缩窗尺寸稳定，
避免把“根本没有缩窗”误判为验收成功。最终同一targeted复测：
**1 passed / 0 failed / 0 skipped，23.071秒，TEST SUCCEEDED**；仍观察980×692。
日志 `/private/tmp/minimum-window-ui-final.log`。两次执行均通过，计为同1项回归用例，
不把重跑累计当作两项独立覆盖；`git diff --check`通过，无xcodebuild进程。
