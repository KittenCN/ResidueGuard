# VM 实际系统验证 — 2026-09-20

## 环境与回滚

客体真实 `sw_vers` / `uname` / `sysctl`：macOS 27.0 / 26A428、arm64、VirtualMac2,1；当前 GUI 用户 uid 501；APFS；`csrutil status` 为 enabled。仅共享项目专用测试交换目录，未共享主目录或密钥。客体终端访问该共享卷时出现系统网络卷许可提示，允许后成功读取测试文件；没有配置 SSH、公共端口或新增宿主隐私权限。

VirtualBuddy 2.2 Beta build 417 的“保存运行状态”明确返回暂时禁用，未视作快照成功。使用先前关机的完整 APFS clone 作基线；从基线再克隆独立验证副本，限制为 2 CPU / 4 GiB、关闭网络和 guest app，实际启动到 macOS 桌面后正常关机。原 VM 仅暂停/恢复，保留用户登录状态。基线原件未启动、未覆盖；原始哈希和 VM 文件仅留本地。

恢复检查证明该磁盘/辅助存储副本可以启动，不等于验证未来全部应用状态恢复，也不等于 VirtualBuddy 运行状态保存可用。

## ISO-01 / ISO-04 正常路径子集：passed

源码夹具入口：`script/build_vm_fixture.sh`、`script/vm_fixture_lab.sh`；自有固定 Label `example.residueguard.fixture.iso01`，ad-hoc 签名、非 root。客体执行显式实验与回滚确认环境开关下的 `bash vm_fixture_lab.sh`，exit 0。时间 2026-09-20 01:10:54–01:10:56 UTC。

实际验证：

1. 同 Label 服务及来源配置原本不存在，当前 GUI 域可查询。
2. 自有 plist 注册后 `state = not running`；精确 kickstart 后 `state = running`，Program/来源路径与自有夹具一致。
3. 源文件身份与 SHA-256 在操作前再次一致；备份与源逐字节相等，模式 0600、单 hardlink，保存 manifest 相关元数据与日志。
4. 精确 `bootout gui/<current uid>/<fixture label>` 成功；后置查询返回该服务不存在，不是域级卸载。
5. 隔离后原路径消失；隔离文件 device/inode/owner/group/mode/link count/size/hash 与原指纹一致。
6. 排他恢复后原指纹一致；再次查询服务不存在，未自动 bootstrap/kickstart。

最终恢复的测试 plist 留在客体中（RunAtLoad=false / KeepAlive=false），实验服务未加载。执行输出、退出码、原始 runtime、日志、备份与指纹已从 VM 导出到受限本地证据目录，未提交用户路径/环境记录。原始 shell 夹具正常路径验证不等于产品 TransactionDriver 验收。

## 仍未通过的门槛

- ISO-01 的重复 Label、未知输出、完整 runtime 冲突矩阵尚未实测。
- ISO-04/M 系列的磁盘满、日志失败、竞争替换、逐步崩溃与恢复冲突尚未做 VM 故障注入；shell 路径操作不具有产品抗 TOCTOU 保证。
- 未检查 BTM 历史是否消失；系统通知出现不代表登记清理验收。无 TCC reset/直读、无 root helper/共享服务测试。
- ad-hoc 只证明本地测试签名校验；不能证明 Developer ID、稳定 helper peer 身份或公证分发。
- 所有产品 mutation gate 继续关闭。不可把正常路径子集改写为整个 ISO/P3/P4 通过。

## 后续开发验证

增加独立 ResiduePersistence 系统 SQLite 日志包，生产执行 gate 保持关闭。主任务复跑 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResiduePersistence`：15/15 通过。状态顺序、持久化防重放及存储异常拒绝已覆盖；尚无进程崩溃/断电或 VM 执行链验收。接口和局限见该包 README；统一入口为 `script/test.sh persistence`。

增加限定 macOS 27 / 26A428 的精确服务运行状态解析器及脱敏客体夹具。初次 Platform 复跑 32 项中一项失败（3 个断言）：字段值自身包含 ` = ` 时错误地被拆为多个字段。修正为只分割首个字段分隔符后，全量 32/32 通过。非成功退出、截断、未知 build、结构/身份冲突均返回 unknown；missing-service 文本不作为可靠不存在证据。未接入 GUI 全系统扫描或开启清理能力。

当前尚未完成客体 GUI 文件选择和扫描验收，也未完成整个项目计划。后续继续真实 GUI 验证、隔离失败路径、日志执行边界与 helper 信任链；签名发布仍需有效身份。
