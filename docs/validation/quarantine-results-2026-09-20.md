# 单文件隔离/恢复原型验证（2026-09-20）

新增独立 `Packages/ResidueQuarantine`，依赖现有Backup API，未改Backup接口。没有公开生产/VM构造入口，无GUI或清理能力门变化。仅随机临时自有夹具文件发生移动和ACL测试，不读取、移动或删除用户真实LaunchAgents，不执行任何服务命令。

环境：macOS 27.0（26A428）arm64、Xcode 27.0（27A266a），Swift 6语言模式，minimum macOS14（未在14实机验证）。参考本机 `man 2 renameatx_np`，采用 `RENAME_EXCL`，不采用覆盖或复制后删除回退。

实际命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueQuarantine`。2026-09-20 13:37运行20项XCTest，0失败。第一轮16项通过，新增4项元数据与恢复竞争测试后20项通过。

覆盖：同inode同卷隔离/恢复、内容/mode/xattr保留、错误计划、源换inode/缺失/符号链接/硬链接、隔离目标已有文件、恢复目标dangling symlink、备份内容与manifest篡改、隔离内容篡改、目的地竞争不覆盖、恢复目标竞争不覆盖、源被竞争替换时移后异常、移后故障、重复隔离、隔离目录权限变宽、隔离目录ACL、隔离文件ACL。

明确观察到的安全边界：测试在最后预检之后、rename之前换入意外对象；rename会移动该对象，随后身份核验失败，返回`movedUnverified`。意外对象保留在隔离名下，原始对象保留在测试指定位置；代码没有自动删除/搬回。此结果是已知竞争风险的正确诊断，不是该风险已经消除的证明，因此不能凭测试通过开放生产清理。

未运行：真实跨卷（未挂载/创建额外卷）、客体VM端到端、进程崩溃/断电、生产根逐级绑定、服务联动、全交易journal、token/有效期与确认流程。代码预检device及EXDEV时拒绝，但本报告不把分支实现视为跨卷实测通过。恢复不会重启服务，不恢复TCC权限。

下一步：审查源命名空间竞争策略，结合持久日志记录`movedUnverified`的只读恢复路径，再以固定自有VM夹具验证完整交易。保持production gate关闭。
