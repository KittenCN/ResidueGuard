# Apple Silicon 上的 Rosetta x86_64 Core 测试

2026-09-20；宿主arm64、macOS27.0/26A428、Xcode27.0/27A266a。
仅使用已经安装的Rosetta与Xcode，不安装组件、不改系统设置、不启动GUI。
不读取用户来源，不执行系统清理。只新增本记录，未改包代码/Package.swift。

## 实际构建与运行

先执行 `arch -x86_64 /usr/bin/true`，退出0。
读取 `swift test --help`、`--help-hidden` 确认 `--scratch-path`、`--arch`、`--skip-build`。
使用独立scratch目录，不污染原arm64构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/ResidueCore \
  --scratch-path .local-evidence/rosetta-core-build --arch x86_64
```

**构建成功，初次执行失败**：该Xcode的swiftpm-testing-helper是arm64-only，
不能dlopen x86_64测试bundle，报告不兼容架构并signal5。swift命令自身也是arm64-only，
用arch包装swift仍报Bad CPU type；未把这些失败改写为通过。

核对现有 `/Applications/Xcode.app/Contents/Developer/usr/bin/xctest` 为arm64+x86_64
通用二进制后，用其公开bundle路径参数直接运行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer arch -x86_64 \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  .local-evidence/rosetta-core-build/out/Products/Debug/ResidueCoreTests.xctest
```

结果退出0；Swift Testing **60 tests passed / 0 failures，1.383秒**。
前面的XCTest层显示0 tests，不能单独算通过；随后Swift Testing确实逐项执行60项并汇总通过。
没有编译替代runner、使用Testing私有入口、下载工具链或更改测试发现逻辑。

## 架构证据与限制

- `file`/`lipo -archs`：测试bundle内 `Contents/MacOS/ResidueCoreTests` 只有 `x86_64`。
- 测试输出：`Target Platform: x86_64-apple-macos14.0`；Testing Library Version 2084。
- `arch -x86_64 /usr/sbin/sysctl -n sysctl.proc_translated`：1。
- 宿主 `uname -m`：arm64。故这是Apple Silicon上的Rosetta执行，**不是Intel硬件验收**。
- 合成10,000条snapshot比较观察0.326723666秒，报告序列化0.925610709秒；仅单次Core观察，
  不作为跨架构性能比较、GUI滚动或扫描速度承诺。

本地日志：`/private/tmp/rosetta-core-tests.log`（SwiftPM runner失败）、
`/private/tmp/rosetta-core-tests-translated.log`（arm64-only swift不能被arch运行）、
`/private/tmp/rosetta-core-xctest.log`（实际60项通过）。scratch与日志不提交。
其他包、x86_64 GUI、真实Intel设备和其他OS均未在本轮运行。

## Platform 追加验证

先审查测试入口：Darwin文件写入仅在本测试新建的UUID临时夹具根内；runtime collector
注入固定捕获，不运行launchctl。进程测试会实际执行只读sw_vers、ls -d /及不存在测试路径、
受限yes/sleep与固定printf shell；不存在主机软件枚举、BTM采集、服务变更或GUI/VM操作。
不能将其描述成绝对没有任何宿主读取，因为OS版本和根目录自身信息确实被只读检查。

本次直接使用已查help确认的构建参数，不重复SwiftPM runner架构失败：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build \
  --package-path Packages/ResiduePlatform \
  --scratch-path .local-evidence/rosetta-platform-build --arch x86_64 --build-tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer arch -x86_64 \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  .local-evidence/rosetta-platform-build/out/Products/Debug/ResiduePlatformTests.xctest
```

构建成功（6.30秒），工具链提示macOS27 deployment target的x86_64架构deprecated，
保留该warning不更改deployment/架构设置。`file`确认实际test bundle为单x86_64；运行日志
Target Platform为x86_64-apple-macos14.0。公开xctest退出0，随后Swift Testing实际执行
**56 tests passed / 0 failures，0.797秒**（前面的0 XCTest仍不单独算覆盖）。

日志 `/private/tmp/rosetta-platform-build.log`、`/private/tmp/rosetta-platform-xctest.log`。
本轮合计Core60项、Platform56项，均为Rosetta运行；不是Intel硬件、多OS或GUI验收。
测试bundle架构已确认，但不声称每个由Process启动的系统工具都使用同一架构。
