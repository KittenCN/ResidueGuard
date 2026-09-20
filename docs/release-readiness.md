# 本地预览与正式发布边界

`./script/package_preview.sh` 仅构建并压缩本地 ad-hoc Debug `.app` 到 git 忽略的 `dist/`，生成 SHA256 清单。它不上传、签名为 Developer ID、公证或安装任何组件。Debug 预览可能包含本机编译调试路径，不应作为正式公开发行包。

`./script/release_check.sh [app]` 只检查：签名有效性、Developer ID Application、hardened runtime、禁止 Debug/temporary-exception entitlement、Gatekeeper。没有身份时失败是正确的阻断结果，不算发布通过。即使这些检查通过，仍须独立验证公证票据、干净系统首次启动、兼容性与每条开放的系统写能力。

正式发布前需要可回滚专用 macOS 环境、有效 Developer ID 身份与开发者控制的公证凭据。凭据不得进入仓库。使用独立 Release archive，核验嵌套代码/entitlement 后再公证、staple 与干净环境验证；不要重新标记 Debug zip 充当正式发行。

当前主程序保持沙箱，用户选择目录只读授权。没有 root GUI、自动 helper、自动后台扫描或自动清理。后续如引入签名 helper，必须先完成隔离环境 peer 身份、路径/范围、重放和自卸载测试，不沿用本地模拟结论开放写能力。
