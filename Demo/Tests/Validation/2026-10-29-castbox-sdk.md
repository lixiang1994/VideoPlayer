# Castbox 迁移所需 VideoPlayer SDK 最小修改（2026-10-29）

状态：实现完成；当前源码真机完整回归 105/105 通过、0 失败、0 跳过，含两分钟真实连续播放；测试与宿主编译、公开接口检查、临时 iOS 15 pod lint 通过。工作区起始干净，基线提交 `20604876ad9e6b54a2ae5be460d474cdf7fd1862`。未提交、未发布、未改版本或 podspec，未修改 Castbox、AudioPlayer 或其他仓库。

## 修改与接口

1. `VideoPlayerConfiguration` 新增 `public var handlesAudioSessionNotifications: Bool = true`。默认保持原行为；false 时 AVPlayer 后端在初始化时不注册 interruption、route change、media services reset 三类通知。App 前后台与 item EOF/失败/卡顿监听不受影响。宿主需要负责这三类会话策略。配置在创建实例时生效，不是运行中可变开关，也不影响显式的音频会话 setup 调用。
2. 增加可选监控能力，不向 `VideoPlayerable` 增加必实现要求，不暴露可变 AVPlayer/item。

```swift
public struct AVVideoNativePlaybackSample {
    public let position: TimeInterval?
    public let seekPending: Bool
    public let rate: Double
    public let sampledAt: TimeInterval
}

public protocol AVVideoNativePlaybackMonitoring: VideoPlayerable {
    var nativePlaybackSample: AVVideoNativePlaybackSample { get }
}
```

`nativePlaybackSample` 必须在主线程读取（实现有 precondition）。`position` 直接采样当前 AVPlayerItem.currentTime().seconds，只有 item.readyToPlay、无 pending seek、数值有限且非负时返回；停止/失败/未就绪/seek 中为 nil。没有乐观目标和 currentTimeCalibrator。`seekPending` 包含准备期间的请求。`rate` 是 AVPlayer.rate 转 Double 的瞬时执行速率，不是用户目标倍率；`sampledAt` 是 ProcessInfo.processInfo.systemUptime 单调秒数。它只证明 item 媒体时钟，不证明物理声画输出。快照没有公开 initializer 或 setter。

宿主示例（普通 import，已独立 typecheck）：

```swift
var configuration = VideoPlayerConfiguration()
configuration.isAutoplay = false
configuration.handlesAudioSessionNotifications = false
let player: VideoPlayerable = VideoPlayer.av.instance(configuration)
let monitoring = player as? AVVideoNativePlaybackMonitoring
let sample = monitoring?.nativePlaybackSample
```

3. 就绪 item 的 seek 可从 `.finished` 立即重开 `.playing` 生命周期，然后走既有 startSeek；不修改 intendedToPlay。该 `.playing` 表示资源 ready，暂停由 control 和播放意图维持。状态广播后重新校验 generation/request，防止重入 stop/seek。显式 0 使用完整请求生命周期。直接 finished→play 仍从头重播；finished→seek→play 从 seek 位置继续。

会话/监控接口及 EOF 变更与用户提供的两份草案一致；将草案三个重复通知开关合并为一个 if。参考 Castbox 的 `docs/patches/playback-sdk/VideoPlayer-session-position.patch`、`VideoPlayer-finished-paused-seek.patch` 和 `docs/testing/audioplayer-migration-finished-seek-draft-2026-10-29.md`（只读参考）。草案中 121 项临时宿主真机通过是先前证据，不能替代本仓库当前源码回归。

## 回归设计与源码 review

现有 97 项保留，新增 8 项，共 105 项（Playback 34、Seek 20、HTTP 16、Session 12、VideoOutput 15、Demo 8）。

- `PlaybackTests.testPausedSeekAndExplicitZeroAfterRealEOF`：真实播放尾部触发 EOF→pause→seek2；3 秒内完成、native≈2/pending=false/rate=0，稳定 0.3 秒；再显式 seek0 并复查，最后 play 实际推进。
- `PlaybackTests.testExplicitZeroDirectlyAfterRealEOF`：真实短视频 EOF 后直接 seek0，一次 began/ended/completion，保持暂停/ready。
- `PlaybackTests.testNativeSampleTracksActualPositionRateAndMonotonicTime`：原生位置推进、目标 1.5 与实际 rate、暂停稳定与单调采样时钟。
- `SeekLifecycleTests.testNativeSampleHidesPendingTargetAndClearsOnStop`：当前显示为乐观目标时 position=nil，失败恢复实际位置，stop 清空 pending。
- `SeekLifecycleTests.testExplicitZeroSeekDuringPreparation`：准备期 seek0 完整一次生命周期。
- `SeekLifecycleTests.testStopWhenSeekReopensFinishedCancelsRequest`：ready 状态回调重入 stop，旧请求取消且不能提交到底层。
- `SeekLifecycleTests.testReentrantSeekWhenReopeningFinishedKeepsNewestRequest`：ready 回调发起新 seek，只提交最新请求。
- `SessionAndRemoteTests.testHostCanDisableAudioSessionNotifications`：三类会话通知不改变 host 意图/资源，切资源仍禁用；App 前后台策略仍生效。既有默认 true 的 interruption、route reset 测试保留。

逐段核对通知注册、clear/deinit、prepare/ready、seek 覆盖和取消、completion 重入、EOF、replay/loop、后台策略以及现有 audioMix 能力。生产改动仅限两个 Swift 文件；未新增 framework/依赖。配置为值类型快照；monitoring 只添加可选协议，旧自定义后端无需实现。未发现新增可确认问题。此为源码 review，不能充当运行通过证据。

## 已执行验证

| 检查 | 结果与限制 |
| --- | --- |
| SDK 可写性 | 普通沙箱 EPERM，require_escalated 写入/删除探针通过；后续授权写入成功 |
| 仓库规则与原改动 | 从根到仓库未发现 AGENTS.md，初始 git status 干净；先读取现有测试和测试说明 |
| Swift parse、podspec Ruby syntax、pbxproj plutil、git diff --check | 通过 |
| `xcodebuild build-for-testing` | Xcode 27.1 / iPhone16 iOS18.6 模拟器，全部当前源码、Demo 与 105 项 XCTest 编译通过，exit 0 / TEST BUILD SUCCEEDED |
| 外部公开 API typecheck | 普通 `import VideoPlayer`（没有 @testable），部署目标 iOS15 arm64 simulator；configuration、builder、optional monitoring 与全部快照字段可从模块外访问，exit 0 |
| 原始 `pod lib lint` | 失败，exit 1：podspec iOS12 超出 Xcode27.1 支持的 15.0...27.1.x；未改声明掩盖问题 |
| 临时 iOS15 `pod lib lint` | exit 0，VideoPlayer passed validation；默认/Core/AVPlayer/Privacy 验证通过；使用 --allow-warnings，日志有 AppIntents metadata extraction skipped 提示；不证明 iOS12 兼容 |

构建命令：

```sh
xcodebuild build-for-testing -workspace Demo/Demo.xcworkspace -scheme Demo \
  -destination 'platform=iOS Simulator,id=2F0EE219-B380-4D82-914B-B28CCAC8A96C' \
  -derivedDataPath /private/tmp/videoplayer-castbox-signed-derived \
  -parallel-testing-enabled NO
```

lint 命令（xcconfig 仅位于 /private/tmp，内容 `IPHONEOS_DEPLOYMENT_TARGET = 15.0`）：

```sh
pod lib lint VideoPlayer.podspec --platforms=ios --allow-warnings --no-clean \
  --validation-dir=/private/tmp/videoplayer-castbox-lint-20261029
XCODE_XCCONFIG_FILE=/private/tmp/videoplayer-castbox-lint-minimum.xcconfig \
  pod lib lint VideoPlayer.podspec --platforms=ios --allow-warnings --no-clean \
  --validation-dir=/private/tmp/videoplayer-castbox-lint-ios15-20261029
```

## 模拟器环境证据与未验证项

首次发现 iOS27 iPhone18Pro 正被 AudioPlayer 使用后，仅终止本任务 xcodebuild，换独立 iPhone17 iOS27。测试服务报 `DTServiceHubClient failed to bless service hub` / `Failed to get valid task for analysis pid`，未进入 XCTest 断言。改用独立 iPhone16 iOS18.6，直接 xcodebuild、默认签名、单独重启该模拟器一次后重试，仍是同一故障。仅停止本任务测试进程，没有全局重启服务或操作真机。主聊天要求保留环境证据、不再重试后，停止模拟器重试。

两项修复前负对照没有完成运行；不能称为“原实现两项失败”。该阶段完整105项模拟器运行没有完成，不能称为通过、失败或跳过105项。中止的 xcresult 缺 Info.plist，不能作有效测试结果；保留文本日志作为环境证据。模拟器阶段未访问设备 `00008140-000D1962348A801C`；随后在主聊天授权排队、确认 AudioPlayer 释放后，接续执行的有效真机全量结果见下节。

真机后仍未验证：真实系统来电/耳机/蓝牙/AirPlay/媒体服务重置、物理声画输出、iOS12 与旧系统矩阵、Castbox transport/工厂的最终集成。通知测试是合成通知策略测试，不能替代真实外设事件。

证据保存在 [同目录证据文件夹](2026-10-29-castbox-sdk/)，包含 [机器摘要](2026-10-29-castbox-sdk/summary.json)、原始/临时 lint 日志、完整测试服务故障日志、独立 build-for-testing 日志、公开 API 检查源码和临时 lint 配置。上述模拟器临时运行产物均在 /private/tmp；它们不是成功的 XCTest 结果。有效真机结果另见下节。


## 最终独占真机完整回归（2026-10-29）

确认 AudioPlayer 真机 xcodebuild 已退出、目标设备 connected 后接续执行，整个 VideoPlayer 运行期间只启动这一轮测试；未并发复跑、未修改源码或测试。iPhone 16e `00008140-000D1962348A801C` / iOS 27.0.1 (24A446)，Xcode 27.1。执行前后的五份源码/测试 SHA-256 与上一轮编译及 review 摘要完全一致。

**实际执行 105 项，105 通过、0 失败、0 跳过、0 expected failure，xcodebuild exit 0 / TEST SUCCEEDED。** 测试用例时长 201.065 秒；xcresult 全程 2026-10-29 16:00:32–16:04:12（Asia/Shanghai，包含准备阶段）。全部组均执行：Playback 34、SeekLifecycle 20、HTTPPlayback 16、SessionAndRemote 12、VideoOutput 15、DemoIntegration 8。

本次无失败用例，不需要针对性复跑。8 个新增用例均在同一完整运行通过，包含真实 EOF→暂停 seek2→显式0、真实 EOF 直接0、准备期0、原生 position/pending/rate/单调时间、重入 stop/seek 以及通知关闭测试。这里的 EOF 是真实媒体自然结束，不是测试手动投递通知；重入用例单独使用受控通知验证确定性竞争，不冒充自然 EOF。

`testTwoMinuteContinuousPlayback` 完整执行，每十秒断言媒体推进，最后附件记录 current=120.237、control=playing、target=1.0。该附件没有系统中断或 App 前后台事件。它证明本轮实际媒体持续推进，不证明物理扬声器或屏幕输出。

命令：

```sh
xcodebuild test -workspace Demo/Demo.xcworkspace -scheme Demo \
  -destination 'platform=iOS,id=00008140-000D1962348A801C' \
  -derivedDataPath /private/tmp/videoplayer-castbox-device-20261029/DeviceDerivedData \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -resultBundlePath /private/tmp/videoplayer-castbox-device-20261029/device-full.xcresult
```

已通过 `xcresulttool get test-results summary` 核对通过/失败/跳过计数和设备信息，并导出完整 test tree 与附件。系统日志含 FigXPC/PlayerRemoteXPC 及 Xcode operatingSystemBuild invalidDigitCount 提示；未阻碍本轮执行，xcresult runtimeWarnings/testFailures 均为空。此前模拟器的 DTServiceHub 故障仍保留为独立环境证据，不能把这些未运行的模拟器轮次标记通过；本轮真机有效结果不依赖它们。

证据：

- 有效结果包：`/private/tmp/videoplayer-castbox-device-20261029/device-full.xcresult`。
- [全量日志](2026-10-29-castbox-sdk/device-full.log)、[xcresult 摘要](2026-10-29-castbox-sdk/device-full-summary.json)、[完整用例树](2026-10-29-castbox-sdk/device-full-tests.json)。
- [附件清单](2026-10-29-castbox-sdk/device-attachments/manifest.json)与两分钟播放时间线均复制到仓库，避免仅依赖临时路径。
- [机器摘要与源码 SHA-256](2026-10-29-castbox-sdk/summary.json)。

测试会话已退出；进程核查无目标设备 xcodebuild，设备已释放交还主聊天。未发布、未提交、未改其他仓库。
