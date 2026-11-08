# VideoPlayer 完整真机回归：2026-11-07

iPhone16e / iOS27.2，Demo scheme Debug，单设备串行执行。最终 **108/108通过、0失败、0跳过**，已交叉核对 xcresult 根指标和逐项日志。

倍速测试在两秒内有界等待 currentTime 与原始 timebase 连续对齐300ms，再执行原来的稳态测速；保留±0.25误差、媒体时钟不得倒退、持续playing及同item断言。未修改生产倍速算法。真实停供/恢复、暂停、切集隔离、密集stall不得制造终止错误均包含在完整回归中。

- DemoTests.DemoIntegrationTests: 8/8
- DemoTests.HTTPPlaybackTests: 19/19
- DemoTests.PlaybackTests: 34/34
- DemoTests.SeekLifecycleTests: 20/20
- DemoTests.SessionAndRemoteTests: 12/12
- DemoTests.VideoOutputTests: 15/15

结果包 `/private/tmp/castbox-video-full-clock-settled-20261107.xcresult`；日志同前缀 `.log`；逐项明细同前缀 `-cases.json`。

源码复核覆盖资源/transport/seek与回调身份、缓冲/目标速率/暂停意图、PCM实时线程与回归证据。没有删除失败用例或放宽倍率断言。

范围限制：系统通知注入不等于真实来电/蓝牙，受控回环HTTP不等于所有公网条件；未完成旧系统真机、物理听感、长时温升耗电和外设验收。Castbox主App本轮公网复验遇到设备No network route/-1009，不能将SDK全通过扩大为主App公网播放验收通过。未发布SDK。
