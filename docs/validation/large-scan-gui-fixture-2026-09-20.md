# 10,000行GUI合成容量夹具

2026-09-20。对应docs/06-tests-acceptance.md 6.7。新增DEBUG专用
`--ui-synthetic-scan --ui-large-scan-fixture`双参数入口；单独large参数不生效，正常
默认路径不变。隔离actor构造10,000条内存合成记录，无文件读取、主机扫描、进程诊断
或额外依赖。记录presence为unknown、能力readOnly，界面保持明确合成标识，不能执行。

首次请求实际生成10,000条记录，稀有标记needle-09999在最后一条，循环检查取消。
第二次请求故意等待30秒，以便稳定验证取消和控件响应；该延迟不是测得的扫描耗时。
取消后返回带cancelled覆盖的实际已构造行，不把未访问状态描述为没有记录。

新增 `LargeSyntheticScanUITests.testTenThousandRowsCanFilterClearAndCancelNextScan`，
位于已有工程成员Tests/UI/ResidueGuardUITests.swift：检查总览实际返回10,000条，进入
记录页筛出稀有末尾项目，清除搜索后恢复首行，保持dry-run不可用，再启动第二次请求，
取消后验证状态与扫描/演示控件可交互。侧栏采用有界滚动确认hittable，不依赖仅exists。

## 实际验证与边界

环境：macOS 27.0 (26A428)、Xcode 27.0 (27A266a)，固定
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
Debug `xcodebuild ... build-for-testing` 成功。
`./script/build_and_run.sh --release-build-only` 成功，并通过 arm64/x86_64
本地 ad-hoc Hardened Runtime、sandbox entitlement 和全部 DEBUG marker 拒绝检查。
其中新增 `--ui-large-scan-fixture` marker；fixture 入口与定义均在 `#if DEBUG`。

定向 GUI 命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ResidueGuard.xcodeproj -scheme ResidueGuard -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build-xcode \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -only-testing:ResidueGuardUITests/LargeSyntheticScanUITests/testTenThousandRowsCanFilterClearAndCancelNextScan test
```

最初两次失败于总数的文案/AX label 查找。失败截图确认实际已显示 10,000 条，
没有把这两次视作产品加载失败。总数 Text 新增稳定 `overview.recordCount` identifier
和有语义的记录数量 accessibilityValue，断言正规化数位后必须等于10000。

第三次总数通过，但进入大表后 AX 查询显著变慢，161.015秒失败于搜索框快照身份失效。
只对该次测试 App 做3秒 `sample`，主线程1580个样本位于
`NSTableRowData._removeRowsBeingAnimatedOff` → `removeViewAndAddToReuse`
→ `NSView.removeFromSuperview` / AutoLayout；该次物理footprint 650.8MiB、峰值1.0GiB。
这是单次观察，不是稳定内存基准，也不能据此认定排序是瓶颈。
尝试给 RecordsView.Table 的变更事务明确禁止行动画后，第四次仍在89.055秒因
搜索框快照身份失效失败。第二次3秒采样主线程823/1635样本在
`XCTElementSnapshotRequest` → `AXUIElementCopyHierarchy`；其中507样本进入
`NSTableViewCellMockElement.accessibilityDescription` →
`viewAtColumn:row:makeIfNecessary` → `rowViewAtRow:createIfNeeded`。
这支持辅助功能快照物化大量行的热点解释，但不把单次样本当完整性能归因。
无收益的禁动画改动已撤回；没有增加测试timeout、分页隐藏记录或修改WorkspaceStore。

实际GUI结果：同1项验收共运行4次，0通过、4失败；前两次是总数定位问题，后两次
已核实10000总数但被大表AX快照阻断，稀有行筛选/清筛选/取消尚未验收完成。
不能把此项标为P6-01完成。新测试保留可复现失败，用于后续专门的大表AX修复。
最后定向运行结束后确认无xcodebuild进程。

当前仍不宣称200ms反馈、1秒取消、10,000行滚动性能达标。
Instruments/signposts仍notRun。原始日志、采样与截图仅本地，不提交个人桌面内容。

后续测试路径调查采用 Apple 公开
[XCUICoordinate](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate)
和 [coordinate(withNormalizedOffset:)](https://developer.apple.com/documentation/xcuiautomation/xcuielement/coordinate%28withnormalizedoffset%3A%29)：
先在少量合成演示记录下取得搜索框实际几何，再在10,000行时使用窗口内坐标和真实键盘输入，
筛选到单行后才查询行的AX属性。没有减少数据规模、修改产品筛选或跳过测试。
第五次尝试发现 macOS `XCUIApplication.frame` 为无限值，不能作为坐标基准；该次
手动中止（退出143），不是产品断言失败。后续改为观察到的window.frame与window.coordinate，
严格拒绝无限值、空frame和窗口外坐标，再允许发送事件。

第六至八次采用有限window坐标后，三次均通过10,000总数及实际筛选：
输入 `needle-09999` 后，末尾行存在、首行不存在、search值正确、dry-run按钮禁用。
其中第七次window级typeText在约14.60秒发事件、16.12秒idle返回；这是一次自动化时间线，
不是稳定延迟或200ms证明。未修改产品、数据规模和超时。
第六次39.413秒、第七次21.180秒、第八次21.207秒失败，均在准备清筛选时触发
XCTest interruption检测：它报告约84×77的Dialog，但随即无法解析该AX identity。
第七次失败截图无可见对话框；同步AX树有键盘聚焦搜索框和唯一匹配行，没有Dialog节点。
第八次改为已筛到一行的search.firstMatch.typeKey仍同样失败，因此不是只在大表下才出现的
全树物化成本。未用自动关闭未知提示、增加timeout或忽略断言掩盖失败。

至此共8次尝试：7次失败，1次主动中止；完整测试尚未通过。已验证加载与末行筛选，
清筛选/取消仍受上述XCTest中断身份失效阻断，不能宣称完整功能验收。
当前测试保留窗口坐标finite/范围验证、实际键盘输入、筛选后AX检查以及未完成的后续断言；
默认测试集不跳过此项。后续需继续排查工具中断或使用独立可靠交互途径，而非改产品使测试通过。

后续分拆验收职责：自动测试明确重命名为
`LargeSyntheticScanUITests.testTenThousandRowsCanFilterLastRecord`，只覆盖目前能够
实际验证的10,000总数、真实键盘筛选、末行存在/首行不存在、搜索值与只读禁用状态。
未跳过此项；移除尚未通过的清筛选/取消断言，不把原完整XCTest标为通过。
清筛选和取消另由主任务在隔离VM内通过真实鼠标/键盘验收，结果需单独记录。
既有独立取消扫描测试不变。新版targeted结果待运行后记录。

## VM真实鼠标/键盘补验

主任务将同一Debug合成容量.app经strict签名验证复制到专用macOS27.0/26A428 VM。通过VirtualBuddy截图与实际鼠标/键盘观察：总览10,000条；列表显示00000等行；输入needle-09999后只显示末尾样本；逐个删除字符清空搜索后首行列表恢复；滚动后可见00006–00010；回总览仍为10,000条。第二次请求采用夹具明确的30秒等待，点击取消后显示“扫描已取消”、未访问不代表没有记录，取消按钮消失，扫描按钮重新可用。

此路线不遍历客体应用的完整AX树，补验了真实UI功能；不把宿主XCTest的旧失败改写为成功。未运行VoiceOver、200ms精确响应或1秒取消统计，不能把工具调用总耗时当作产品时延基准。没有修改真实来源或开启系统动作。宿主直接CUA选择本App会返回native pipe closed，选择VirtualBuddy正常，该工具问题也未伪装成产品修复。

## 最终收窄自动验收

运行上述定向命令，将 `-only-testing` 改为
`ResidueGuardUITests/LargeSyntheticScanUITests/testTenThousandRowsCanFilterLastRecord`：
**1 test，0 failures，18.358秒，TEST SUCCEEDED**。
该时长包含启动/导航/自动化等待，不是扫描或输入延迟。
此结果仅证明重命名后的总数与末行筛选用例通过；原含清筛选/取消的版本失败记录仍保留。
清筛选、列表恢复/滚动与取消的功能证据来自上节VM真实交互。

最终含Overview AX变更再次运行 `./script/build_and_run.sh --release-build-only`：
BUILD SUCCEEDED；x86_64与arm64本地Release签名/entitlement检查通过，App Sandbox、
用户选择只读、无debugger entitlement、无DEBUG注入marker。该检查不代表分发签名或GUI验收。
