# 固定自有服务 bootout：VM 单次实际结果

环境：VirtualMac2,1，macOS 27.0/26A428，当前专用普通用户，SIP保持开启；宿主构建使用Xcode 27/27A266a。生产gate关闭。

VirtualBuddy保存状态功能返回暂不可用，因此在客体正常关机后建立独立APFS clone副本，核对7个文件的集合与大小，然后启动原VM。此新副本尚未单独启动验收；此前clean baseline已做过启动验证。未复制正在运行的磁盘、未修改锁屏或安全设置。

重启后原共享目录未挂载，首次shell调用报脚本不存在，未运行probe；重新挂载既有共享目录后，唯一的bootout-v1 probe实际运行。wrapper使用唯一目录与结果文件拒绝重复执行，并在客体本地复制后核对SHA256/严格签名。

## 实测

- probe exit **0**，只发出一次固定service-target bootout；命令exit0，launched=true，约0.0083秒，双流为空、无截断、无capture failure。
- 动作前两次观察要求registeredNotRunning；已验证备份与源/程序身份，独立durable intent/preflight先于动作，outcome先于后置观察。
- 后置固定print exit **113**，stdout为空，stderr为当前target的“Bad request / Could not find service”诊断；约0.0074秒，无截断或capture failure。
- 后置仍为 **unknown / partial / absenceProven=false**，未经验证的诊断不改变模型为absent。源配置与程序身份仍匹配，filesUnchanged=true。
- 没有bootstrap、隔离配置、恢复加载、提权或其他服务操作；生产动作仍关闭。
- 正常流程独立readOnly日志实例重开4槽通过。四份本地私有证据副本的payload SHA256逐一验证通过；这不是对同UID写入者的认证。

原始日志及实验UUID仅保存在忽略的.local-evidence中。随后独立BootoutAuditProbe在VM实际exit0：complete、1条实验/4槽、failedLogs=0、refusedRoots=0、其他8个实验根无此日志。独立进程读到command0/post113与保存的原始摘要一致，postRuntime仍unknown、freshFilesInspected=false，历史文件匹配不冒充新的文件检查。取消、超时、命令发出期间崩溃等真实VM矩阵尚未完成。

本次只证明固定自有夹具的单次正常命令路径，不证明第三方注册卸载安全，也不证明应用或配置文件已删除。服务身份核验到bootout之间仍无原子比较交换契约。
