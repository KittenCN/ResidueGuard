# 备份原型验证（2026-09-20）

范围：新增独立 `Packages/ResidueBackup`，仅使用随机临时目录和自有夹具。本机测试不读写用户 LaunchAgents，不操作任何服务，不提供生产构造入口，不修改清理能力门。

环境：macOS 27.0（26A428）、arm64、Xcode 27.0（27A266a）、Swift 6 语言模式，最低部署版本 macOS 14（未在 macOS 14 实机运行）。

实际运行：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueBackup`。

17 个 XCTest 通过：备份读回/源不变、源内容变化、同内容换 inode、基名路径遍历、源符号链接/硬链接、不安全文件模式、扩展属性原字节保存、超大文件、内容篡改、manifest 篡改、目的根权限变化、FIFO非阻塞拒绝、源 ACL、备份 ACL、备份硬链接，以及只读源目录0755允许但目的根0755拒绝。测试使用真实公开 Darwin 文件 API，属于自有临时夹具文件系统测试，不算 VM 端到端清理证明。

开发中最初编译因 Swift ACL 类型桥接失败，修正后首轮因系统 provenance xattr 与 absent ACL 语义失败。已改为有界保存全部源 xattr，并在已验证打开 fd 上识别 Darwin 的 absent ACL `ENOENT`；实际带 ACL 夹具仍被拒绝。依据当前 SDK、本机 `acl_get_fd_np(3)` / `acl_get_entry(3)` 和真实测试；没有将任意错误当成无 ACL。

限制：没有逐级固定生产根工厂、GUI连接、source mutation、恢复或服务执行；没有崩溃故障注入和穷尽竞争测试；不抵御拥有同 UID 完全控制的攻击者。扩展属性保存在 manifest，尚未验证恢复应用，不声称“恢复元数据/权限”。失败可留下不完整私有备份目录。production gate 继续关闭。下一步是独立测试崩溃恢复与固定根绑定，再在 VM 自有夹具验证 typed executor 的整个事务，不以本报告单独启用清理。

## VM probe 构建及宿主拒绝

新增 `ResidueBackupVMProbe`：只接受真实 VirtualMac、非root、当前用户固定ISO01夹具，执行固定源备份和读回校验，没有任意路径参数。通过 Security framework 检查固定fixture的严格签名及identifier，逐级no-follow验证目录。目的地为执行端生成的随机私有VM实验根。没有生产工厂或系统修改操作。

实际运行 `.build/debug/ResidueBackupVMProbe` 于宿主返回77，输出 `REFUSED: non-root VirtualMac guest required`，没有触及真实 LaunchAgents。构建及17项测试通过；此报告此时尚不声明该probe已在客体运行通过，待主任务补充客体结果。

## 真实 VirtualMac 验证

主任务将 strict codesign 校验通过的 probe 复制到客体专用本地目录，执行无参数固定 ISO01 入口：exit 0，输出 `PASS ISO01 verified backup; sourceUnchanged=true; runtime=notInspected; productionGate=disabled`。客体 macOS 27 / 26A428，源为既有自有 fixture。实际创建私有备份、内容/manifest 读回和源指纹复核均通过；没有修改来源配置、卸载服务或自动恢复。原始结果和随机 backup ID 仅留本地。
