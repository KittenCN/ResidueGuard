# 覆盖范围约束的观察快照比较

2026-09-20。覆盖范围约束的比较、GUI接线和已授权配置根的局部复扫现已实现；不改变presence、候选归属或清理能力。下文保留各阶段实际验证记录，以末节结果为当前状态。

新增ObservationSnapshot显式记录generation、ScopedSnapshotRecord和SnapshotComparisonCoverage；scope键包含providerID/userScope/declaredRoot/osBuild。根字符串按字面比较，不解析路径或获得授权。调用方须把每条记录绑定其实际采集范围，不能凭路径前缀把别处记录归入授权根。

SnapshotComparison的新重载输出firstObserved、changed、notObserved、ambiguous、limitedScopes、diagnostics。firstObserved只是两轮输入中的首次观察，不是安装事件。共同观察的同身份记录可比较内容，但范围改变显式受限。notObserved仅来自两次不同代次、同一scope且完整的输入；仍不证明删除。取消、partial、denied、unsupported、重复coverage/record身份、混代、未知或复用generation、无效绑定不能支持相关负面观察。scope/OS变化不从缺行推断删除。输入上限20000记录和256coverage，达到上限明确拒绝比较，不静默截断。旧数组API保持兼容，适用于低层记录差异，不具覆盖保证。

GUI建议调用canUseAsBaseline(snapshot:providerIDs:)仅关心launchd.configuration；相关所有范围完整且有效才更新比较基线，取消/partial保留上一个完整基线，但当前部分结果仍可显示。无关unsupported BTM不阻断配置基线。首次失败不会成为基线；根改变仍输出scopeChanged。GUI输入宜只包括当前配置记录和对应明确declaredRoots/userScopes，不为无授权根的unsupported provider编造空根。后续如引入逐scope基线缓存，保留每组原始generation；不要无标记合并成单代次当前快照。

实际命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/ResidueCore
```

结果：**58 tests通过，0失败/跳过，0.425秒**，其中新增8项测试：不同完整代次的内容比较；5种不完整coverage；3种根/build/user范围改变；无关unsupported不阻断；混代/错误绑定；重复identity/coverage；取消后保持基线避免伪新增；未知/复用代次和资源上限。旧2项数组比较及其余Core回归均通过。git diff --check通过。未运行GUI/Xcode UI tests，不将此报告视为局部复扫完成。

## 后续：GUI绑定审查与10,000记录比较

只读检查WorkspaceStore的comparisonObservation与baseline更新：当前真实ScanService逐配置根
返回单declaredRoot、单userScope，失败根仍产生coverage；adapter以精确父目录、provider、
scope绑定，由Core检查记录和coverage代次。取消/partial/根截断不替换基线，切换demo清空
基线。未在此当前provider契约下发现错误scope/generation绑定，未修改GUI。

后续防御边界：adapter的flatMap会丢弃无declaredRoots/userScopes的coverage，未来provider
若漏维度且无记录，须显式保留不可比较状态而非把剩余根视为完整；多根×多scope笛卡尔积也
不应代替真实关联关系。当前collector的一根一scope结果没有触发这两种情况。

新增10,000→10,000条合成SourceRecord的实际比较测试，准确断言首次观察1,000、内容变化
1,000、同完整范围未再观察1,000，其余8,000条共同对象不变；无身份冲突或范围限制。测量
比较函数本身耗时 **0.230880292秒**，该测试含构造/断言 **0.256秒**。未设机器特定速度
门槛，计时使用单调时钟。输入/输出类型均没有presence、capability或执行token，不导入
Platform扫描模型；这不是主机扫描或GUI渲染性能证据。

同一固定Xcode命令完整Core回归：**59 tests通过，0失败/跳过，0.596秒**。本项仅改Core测试
及本文档；未运行GUI或访问真实扫描来源。

## GUI接线与局部复扫

WorkspaceStore只为launchd.configuration构造比较范围，要求provider每条coverage恰有一个root/userScope；空维度或多对多保持无效，不能静默丢弃或构造笛卡尔关联。记录必须以来源文件直接父目录精确绑定，Core复核代次与身份。没有完整基线时不假称保留旧观察。比较计算放utility任务，主线程仅发布结果。

局部复扫只接受configuredLaunchRoots成员，其余已授权配置根追加partial/notRequested覆盖，候选图/记录只来自新请求，不混合旧代次。应用索引仍按原先授权范围读取。这样未请求目录不产生缺失推断，也不会替换全配置比较基线。没有新增目录权限或自动持久化授权。

首次targeted UI启动因宿主锁屏/LocalAuthentication正在运行而失败，测试尚未执行；解锁后基线用例通过。局部复扫用例首次按PopUpButton查找SwiftUI Menu失败，修为实际可访问元素标识查找后通过（11.241秒），未修改功能以迎合断言。完整GUI回归已完成：22项中21项通过、1项真实文件选择器用例显式跳过、0失败，273.497秒。两个新增用例覆盖不完整扫描保留基线与局部复扫遗漏范围不产生缺失推断。宿主macOS 27.0/26A428，Xcode 27/27A266a。真实文件选择器另有此前VM专项证据，不计入本次通过数。

本地Release打包命令 `./script/package_local_release.sh` 通过：arm64/x86_64严格签名与只读沙盒授权检查、无debugger授权、七个Debug测试开关不进入Release、ZIP解包后再次验证通过。未声称Intel运行或公证验证。
