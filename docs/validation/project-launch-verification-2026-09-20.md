# 项目启动进程识别（2026-09-20）

原启动脚本用 `pkill -x ResidueGuard` 停止进程、用 `pgrep -x ResidueGuard` 判断启动。这会把其他构建目录中的同名进程纳入操作，且不能证明当前项目可执行文件已启动。

新增 `project_app_process.py` 只接受固定操作名，目标限定当前项目 `.build-xcode/Build/Products/Debug` 或只读检查的 Release。用 pgrep 取得候选 PID 后，必须再通过 macOS `proc_pidpath` 核对真实可执行文件路径。停止只针对项目 Debug，等待最多3秒；不自动强杀未退出进程，也不继续启动重复实例。验证/调试 PID 必须唯一，多个同路径进程明确拒绝。

`build_and_run.sh --verify` 改为核对该项目路径；LLDB和日志模式使用取得的精确 PID，不再按所有同名进程匹配。它只证明进程存在，不替代 GUI、业务或签名验收。

## 实际验证

环境 macOS27/26A428，Xcode27/27A266a。

- `bash -n script/build_and_run.sh` 通过。
- 停止项目 Debug 后，verify-debug 实际退出1，明确“Expected project app executable is not running”。
- 在自有随机临时目录运行一个同名的独立 sleep 夹具。stop-debug 没有停止它，verify-debug 仍退出1；夹具由测试父进程结束并等待回收，临时目录已清理。
- 夹具首次使用copy2时试图复制系统文件flags，被系统拒绝；改为仅复制字节并设置自有文件执行mode、ad-hoc签名，未修改原系统文件或平台保护。该首次夹具准备失败不计测试通过。
- `./script/build_and_run.sh --verify` 实际构建成功、启动 `.app`，并打印经路径验证的唯一Debug PID。pid-debug返回同一PID。

本轮未实际附加LLDB，也未运行持续日志会话；其参数路由仅经脚本语法与PID生成检查。没有停止其他路径的ResidueGuard、VM或第三方服务。
