# 在线缓冲过早终止：源码与既有真机证据复核（2026-11-06）

当前原 SDK 中的缓冲修复和全部测试，逐文件 SHA-256 匹配 2026-11-05 隔离候选真机全量 **108 通过、0 失败、0 跳过** 的源码摘要。本次在专用聊天复核并归档证据，没有重新占用 iPhone 16e。不能把既有候选运行写成今天原仓库重新运行。

## 具体源码结论与最小修改

旧实现关闭 `automaticallyWaitsToMinimizeStalling`，许可播放时调用 `playImmediately(atRate:)`；每次收到 `AVPlayerItemPlaybackStalled` 再次强制播放。相邻 stall 通知间隔小于 1 秒时计数累积，第 11 次不检查 item.error 就制造 `Playback Stalled/-111111`，随后 clear 当前资源。这会把可恢复的数据暂缺升级为终止失败。计数是短间隔通知链，不能误写为任意历史卡顿累计。

Castbox 真实 TED 视频 URL `https://download.ted.com/products/197241.mp4?apikey=172BB350-0205` 从 61 秒、1.1 倍速播放，约 73 秒出现上述自定义失败；item ready、bufferEmpty=true、likely=false、item.error=nil，accessLog 仍收数据。主聊天独立原生对比继续等待且间歇推进，但属于顺序网络观察，不能作为控制变量 A/B 的证明。

当前生产改动只在 `Sources/AV/AVVideoPlayer.swift`：

- 开启 AVPlayer 自动缓冲等待。
- iOS16+/tvOS16+ 设置 `defaultRate` 后 `play()`，保留目标倍速并允许系统等待；旧系统设置 `rate`，旧系统实际行为尚未设备验证。
- stalled 通知仅刷新实际 control/loading，不强制重播，也不制造终止错误；移除计数及清理字段。
- 原有 item.failed 与 failedToPlayToEnd 错误入口保留。用户 pause、seek、stop、切资源、中断和后台限制仍由原播放意图、generation、item 身份与 seek 请求校验约束。

这些修改由主聊天于 2026-11-06 写入原 SDK，本次读取时已存在；本聊天未覆盖现有生产补丁，未改安装 Pods、版本、线上配置或其他仓库。基线版本为 5.3.2（此前会话/原生监控修改已由其他操作提交），本轮缓冲补丁未发布。

## 测试覆盖及证据范围

主聊天隔离候选使用现有本机 HTTP 服务新增三项测试：

1. `testRepeatedStallNotificationsDoNotInventFailure`：就绪本地 item 上投递 20 次密集 stall，保持资源且继续推进。这是通知处理策略测试，不冒充真实带宽复现。旧实现运行同一测试 1 项失败，候选通过。
2. `testStreamRecoveryPreservesSelectedRate`：长 MP3 分块供数后真实停供，等待真实系统卡顿，恢复供数，要求媒体推进且实际 rate=1.5、目标倍率保留。
3. `testSwitchWhileStreamStalledRejectsOldNotification`：真实停供后切到另一资源，旧 item 通知和旧供数不能影响新 item，保持暂停。

现有真实断流恢复、卡顿时暂停不恢复、准备/seek/stop/资源切换、EOF、视频输出、媒体时钟倍率和两分钟连续播放用例均在同轮完整运行。HTTP 19/19、Demo 8/8，全套108项逐项 Success；iPhone16e / iOS27.2，228.453秒。既有记录说明运行关闭隔离测试的 Debug executable，以绕过 LLDB 附加问题；此前中断轮次不计作产品通过或失败。

有明确限制：这些网络测试是可控分块停供/恢复，尚未建立持续边缘带宽下“多次缓冲→持续收数据→最终恢复”的严格受控 A/B；真实 MP4/CDN/header/start61/rate1.1 场景仍由 Castbox 主聊天联调。不能将合成通知反证等同于公网自然产生11次卡顿的反证。自动等待可能先进入 waiting 而不发 stalled，未来持续带宽用例应同时采集 timeControlStatus、媒体时钟冻结、服务供数字节，不应把通知次数当作全部缓冲状态。

## 本次复核

- SHA-256：18份摘要文件全部匹配，含全部10份生产 Swift 文件、7份测试/夹具源码及1份旧公开 API 检查源码；逐项结果见机器摘要。
- `git diff --check`、Swift语法解析、podspec Ruby语法通过。
- 本次没有运行模拟器或真机测试。普通沙箱 simctl 只读查询被服务权限阻止；未重启或修改设备。
- Xcode27.2 (27B52) 下本地 `pod lib lint VideoPlayer.podspec --platforms=ios --allow-warnings --no-clean` exit 0 / VideoPlayer passed validation，覆盖默认及 Core/AVPlayer/Privacy 子规格。通过 `XCODE_XCCONFIG_FILE` 临时覆盖部署目标为15.0；未改 podspec 的iOS12声明，因此不证明iOS12兼容。日志只有 AppIntents metadata extraction skipped 提示。[完整日志](2026-11-06-buffering/lint.log)及[临时配置](2026-11-06-buffering/lint-minimum.xcconfig)已归档。

有效既有结果包：`/private/tmp/castbox-v2-buffering-sdk-final.xcresult`；反证：`/private/tmp/castbox-v2-buffering-sdk-baseline.xcresult`。新式 xcresult summary 在当前环境无法写入 TestReport，保留错误，不用空摘要推断测试结果。采用主聊天已导出的 legacy object、逐项108项清单与源码摘要交叉核验。

仓库归档：[机器摘要](2026-11-06-buffering/summary.json)、[108项及反证完整清单](2026-11-06-buffering/candidate-device-evidence-20261105.json)、[候选原始结果对象](2026-11-06-buffering/candidate-result-object.json)、[反证结果对象](2026-11-06-buffering/baseline-result-object.json)。原始 Castbox 证据只读参考 `docs/testing/playback-acceptance/v2-sdk-buffering-candidate-2026-11-05.md/.json`、`v2-native-diagnostic-2026-11-05.md`、`v2-native-buffering-2026-11-05.json`。

剩余验证：持续边缘带宽受控实验、Castbox最终TED主App联调/日志/UI、旧系统rate分支和iOS12兼容、真实外设及物理声画输出。本报告不替主聊天签署主App验收。
