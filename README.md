# VideoPlayer

基于 AVPlayer 的轻量 iOS 视频播放器封装。统一资源状态、播放控制和代理回调，输出可嵌入业务界面的 `VideoPlayerView`。保留自定义后端能力，适用于本地视频、HTTP 点播和 HLS 播放。

播放器负责播放生命周期；音频会话、界面、画中画和音效算法由宿主配置。Demo 提供完整界面和可运行案例。

## 特性

- 网络 / 本地资源播放，自动播放、暂停、重播、循环和倍速。
- 准备期间寻时、连续拖动、取消和资源切换保护；seek completion 只完成一次。
- 分离资源状态、实际控制状态和加载状态，多播弱引用代理。
- 跨资源复用 AVPlayer、AVPlayerLayer 和输出视图，保留布局与 PiP 绑定。
- 完整显示、裁剪填充和拉伸；当前解码画面截图，支持旋转信息。
- 外部传入 `AVAudioMix`，同 item 更新音轨处理配置，无需重新 prepare 或 seek。
- 系统中断、输出设备断开、媒体服务重置和可选后台播放策略。
- 可选锁屏播放信息与遥控封装。
- Demo 覆盖 MP4、MOV、HEVC、竖拍、无音轨、mix、截图和 PiP。

## 环境与安装

库的 podspec 声明 **iOS 12.0+、Swift 5.2**；Demo 使用 **iOS 15.0+、Swift 5**，已迁移 Scene 生命周期以适配当前 SDK。旧系统最低版本声明不代表本轮已经在 iOS 12–14 真机回归。实际验证环境与限制见 [验证记录](Demo/Tests/DEVICE-VALIDATION.md)。

### CocoaPods

当前 Xcode 27 的 SDK 最低支持 iOS 15，因此在该工具链下构建宿主请使用 iOS 15+。库仍保留 iOS 12 的兼容声明；完整验证 iOS 12 部署目标需要选择支持它的旧版 Xcode，不能把新 SDK 的部署范围错误视为源码编译错误。


```ruby
platform :ios, '15.0'
use_frameworks!

pod 'VideoPlayer'
```

默认包含 Core 与 AVPlayer 后端。仅使用通用协议可选择 `VideoPlayer/Core`。本轮更新尚未发布到 CocoaPods；测试当前源码时使用本地路径或固定到包含修改的 Git 提交：

```ruby
pod 'VideoPlayer', :path => '/path/to/VideoPlayer'
```

仓库暂未提供 Swift Package Manager 的 Package.swift；也可以集成 `VideoPlayer.xcodeproj`，链接生成的 framework。请勿把 Demo 的界面与 PLPlayerKit 适配器当作默认库依赖。

## 快速使用

在主线程创建、调用、读取及释放播放器，代理和 completion 也在主线程回调。业务必须持有播放器实例；仅持有输出视图不会保活播放器。

```swift
import UIKit
import VideoPlayer

final class PlayerViewController: UIViewController, VideoPlayerDelegate {
    private let player = VideoPlayer.av.instance()

    override func viewDidLoad() {
        super.viewDidLoad()
        player.add(delegate: self)
        let videoView = player.view
        videoView.frame = view.bounds
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoView.contentMode = .scaleAspectFit
        view.addSubview(videoView)

        // 会话属于整个 App；生产应用应由统一会话管理器配置并处理配置失败。
        VideoPlayer.setupAudioSession(in: .audioSession) { [weak self] in
            guard let self = self else { return }
            self.player.prepare(resource: URL(string: "https://example.com/video.mp4")!)
        }
    }

    func videoPlayerState(_ player: VideoPlayerable, state: VideoPlayer.State) {
        if case .failed(let error) = state { print(error as Any) }
    }

    deinit { player.stop() }
}
```

`setupAudioSession` 是便利接口，在指定队列配置 `.playback` 并在主线程完成；旧接口只打印配置错误，不通过 completion 返回错误。需要可靠错误处理时请直接管理 `AVAudioSession`，也应在页面退出时取消尚未完成的准备意图。Demo 使用资源代次保护迟到回调。

本地文件使用文件 URL：

```swift
let url = Bundle.main.url(forResource: "sample", withExtension: "mp4")!
player.prepare(resource: url)
```

也可以传入 `AVURLAsset`，保留其加载选项和音轨身份。`prepare` 默认自动播放，停止会清除资源；停止或失败后重试需要重新 prepare。

## 控制与状态

```swift
var configuration = VideoPlayerConfiguration()
configuration.isAutoplay = false
configuration.preferredBufferDuration = 3
configuration.currentTimeCallbackPeriodicInterval = 10
let player = VideoPlayer.av.instance(configuration)

player.prepare(resource: url)
player.play()
player.pause()
player.rate = 1.5       // 暂停期间只保存设置，不起播
player.volume = 0.5     // 0...1，不提供超过原始音量的增益
player.isMuted = false
player.isLoop = true
player.seek(to: .init(time: 30) { finished in
    // false 包含覆盖、stop、切资源和系统取消。
})
```

| 属性 | 含义 |
| --- | --- |
| `state` | `.stopped → .prepare → .playing → .finished`，异常进入 `.failed` |
| `state == .playing` | 沿用旧 API，表示资源已就绪；暂停时仍可能处于该状态 |
| `control` | `.playing` / `.pausing`，表示实际控制状态；卡顿期间可能暂停 |
| `loading` | `.began` / `.ended`，表示准备或等待数据 |
| `current` / `duration` | 媒体秒数；未知时长返回 0，不能据此判断直播已结束 |
| `buffer` | 有限时长资源的已加载范围终点比例，限制在 0...1；不是“连续可播放缓冲秒数” |

准备完成前也可提交 seek；连续请求以最后一次有效。点播寻时限制在可用范围，HLS 直播受实际可寻时窗口约束。精确 seek 可能需要网络请求与重新解码，不能保证零延迟。finished 后直接调用 play 从头重播；暂停时 seek（含显式 0）立即执行并重开 `.playing` 就绪生命周期，完成后保持暂停，随后 play 从寻时位置继续。

AVPlayer 后端提供可选只读原生监控；通过能力转换使用，不要求其他后端实现：

```swift
if let monitoring = player as? AVVideoNativePlaybackMonitoring {
    let sample: AVVideoNativePlaybackSample = monitoring.nativePlaybackSample
    let position: TimeInterval? = sample.position
    let pending: Bool = sample.seekPending
    let actualRate: Double = sample.rate
    let uptime: TimeInterval = sample.sampledAt
}
```

在主线程采样。`position` 直接读取当前 `AVPlayerItem.currentTime()`，就绪、无 pending seek 且秒数有效非负才有值；未准备、停止、失败或 seek 中为 nil。`seekPending` 包含准备期间等待提交的请求；`rate` 为 AVPlayer 瞬时速率，暂停时为 0，区别于 `player.rate` 的目标速率；`sampledAt` 为 `ProcessInfo.processInfo.systemUptime` 单调秒数。原生采样不使用 `current` 的乐观 seek 目标或校准值，不证明扬声器或屏幕物理输出。快照成员均为只读，未公开 AVPlayer 或 item 的可变引用。

代理使用 `add(delegate:)` / `remove(delegate:)` 管理。回调允许同步暂停、停止或切资源；引擎会丢弃已经失效的旧事件。独立页面推荐 `instance()`；`shared` 是进程内共享实例，使用者必须自行协调所有权。

## 画面与截图

```swift
player.view.contentMode = .scaleAspectFit   // 完整显示，默认
player.view.contentMode = .scaleAspectFill // 裁剪填满
player.view.contentMode = .scaleToFill     // 拉伸

player.screenshot { image in
    // 主线程回调。尚未解码、纯音频、停止或请求期间切资源时可能为 nil。
    imageView.image = image
}
```

截图来自当前 AVPlayerItemVideoOutput 的真实解码帧，不重新下载资源或进行额外 seek。旋转信息异步加载；截图可能异步完成。输出为普通 UIImage，不承诺保留 HDR 色彩元数据，也不适用于受保护内容。

## 外部 AVAudioMix

对本地或普通 HTTP 文件，使用与播放 item **同一个 AVURLAsset** 的音轨创建 mix。先异步加载音轨，再提交资源：

```swift
import AVFoundation

let asset = AVURLAsset(url: url)
asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
    DispatchQueue.main.async {
        guard asset.statusOfValue(forKey: "tracks", error: nil) == .loaded else { return }
        let mix = AVMutableAudioMix()
        mix.inputParameters = asset.tracks(withMediaType: .audio).map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(0.25, at: .zero)
            return parameters
        }
        player.prepare(resource: AVVideoPlayerResource(asset: asset, audioMix: mix))
    }
}
```

动态切换时保留同一 asset，通过可选能力更新当前 item：

```swift
let mixing = player as? AVVideoAudioMixControlling
let accepted = mixing?.update(audioMix: mix, for: asset)
mixing?.update(audioMix: nil, for: asset) // 恢复原始处理
```

该接口不替换 item、不 seek、不修改倍速或播放意图。asset 身份不符、停止或无 item 时返回 false；true 只表示提交成功，不能证明内容或输出路由支持处理。`AVVideoPlayerResource` 初始化复制 mix 配置，后续修改原对象不会自动更新已提交资源。tap 的内部状态仍由调用方同步管理。

AVAudioMix 的普通音量参数适合衰减、渐入和渐出；**2 倍音量增强需要自行提供 MTAudioProcessingTap / PCM 增益处理**。频繁切换效果应复用已安装的 tap 并更新线程安全参数；任意替换 mix 可能使系统重配音频链，不能承诺绝对无听感变化。库不内置增益算法、静音检测或静音加速。

## 格式与资源兼容性

格式由系统 AVFoundation、容器内编码、设备和系统版本共同决定；扩展名不是可播放保证。

| 资源 / 格式 | AVPlayer 后端 | 本轮验证范围 |
| --- | --- | --- |
| 本地 file URL | 支持系统可解码的资源 | MP4/H.264+AAC、MOV、HEVC、竖拍、无音轨视频 |
| 普通 HTTP / HTTPS 文件 | 支持；seek 依赖服务器 Range、索引与网络 | 真机本机 HTTP MP4、Range、重定向、错误、延迟和断流 |
| HLS `.m3u8` | 支持系统兼容的点播 / 直播 | 真机本机 H.264/AAC 视频 HLS 点播和 seek；直播未实测 |
| MP4 / M4V / MOV | 常见 H.264 + AAC 组合适合作为默认选型 | MP4、MOV 实际视频帧；M4V 未单独实测 |
| HEVC / H.265 | 依赖设备、系统与编码参数；建议 hvc1 | 当前真机的 MP4/HEVC 样本；不覆盖所有 profile |
| 纯音频 AAC / MP3 等 | 可兼容播放，不输出视频截图 | 本地 AAC、HTTP MP3、音频 HLS 回归 |
| MKV / FLV / AVI / WebM / RTMP | 不作支持承诺，通常需要转码或其他后端 | 未验证 |
| DRM / FairPlay、HDR、Dolby Vision | 没有专用授权或色彩管理封装 | 未验证，不在本轮保证范围 |

| mix / tap 场景 | 边界 |
| --- | --- |
| 本地带音轨文件 | 推荐；Demo 25% 开关与自动化验证使用此路径 |
| 普通 HTTP 音视频文件 | AVFoundation 允许的文件型资源可使用 mix；测试覆盖配置和播放保持，不代表所有 CDN / 编码 / tap 算法有效 |
| 无音轨视频 | 没有可处理的音轨，页面明确提示 |
| HLS、直播、受保护内容 | 不承诺 AVAudioMix / MTAudioProcessingTap 生效；不能把可播放等同于可处理 PCM |
| 蓝牙 / AirPlay / 外部播放 | 处理位置及能力由系统决定，本轮未实测 |

生产网络建议 HTTPS。Demo 为本机 HTTP 测试放开 ATS；宿主应按自己的域名和安全策略配置。带鉴权的资源可传入配置好的 AVURLAsset；库不额外实现缓存、下载、断点续传或 HTTP 请求代理。

## 后台、锁屏与画中画

宿主配置 `.playback` 音频会话和 Background Modes → Audio, AirPlay, and Picture in Picture。会话错误应由宿主处理。可选策略：

```swift
(player as? VideoPlayerBackgroundControlling)?.allowedBackgroundPlayback = false
```

后台许可默认 true；false 时后台暂停，回到前台按保留的用户意图恢复。用户主动暂停会取消恢复。

音频会话通知默认由 SDK 处理：系统中断结束需 shouldResume；耳机断开暂停；媒体服务重置报告失败，宿主应重新配置会话并 prepare。宿主已有统一会话管理器时，在创建实例前关闭这三类监听：

```swift
var configuration = VideoPlayerConfiguration()
configuration.handlesAudioSessionNotifications = false // 默认 true
let player = VideoPlayer.av.instance(configuration)
```

false 时宿主负责 interruption、route change 和 media services reset；SDK 不注册这三类通知，不影响 App 前后台策略或当前 item 的结束、失败、卡顿通知。配置是创建时的快照，不能对已有 shared 实例补设。此开关不配置或激活音频会话，也不改变宿主显式调用 `setupAudioSession` 的效果。

后台许可不等于系统保证视频持续播放。视频层绑定、PiP 状态、内容和系统策略都会影响后台行为；本轮通知策略测试不能替代真实来电、蓝牙、AirPlay、锁屏或 PiP 测试。

可用 `VideoPlayerRemoteControl(player)` 管理锁屏播放 / 暂停与播放信息，宿主持有该对象并设置元数据；它操作的是全局系统中心，应统一管理多个播放器的竞争。

PiP 属于 Demo 的 `PictureInPicture` 桥接示例，不是库自带的全局播放服务。请使用 `player.view.playerLayer as? AVPlayerLayer` 构造 AVPictureInPictureController，并等待系统允许开启。跨页面播放与恢复导航需要宿主保持播放器、控制器和页面路由；Demo 返回列表会停止播放。

## 运行 Demo 与测试

```sh
cd Demo
pod install
open Demo.xcworkspace
```

选择 Demo scheme、自己的开发签名和设备，使用 workspace 运行。默认只依赖 AVPlayer 与 SnapKit。首页区分网络与本地案例。网络页可选 HLS 和普通 HTTPS MP4；HLS 禁用 mix 并显示原因，MP4 可对比原始音轨与 25% 配置。本地页默认“MP4 有声”包含可试听的测试音，可以切格式、倍速、显示模式、音量 mix 以及截图；“无音轨”案例特意没有声音，不用于 mix 音量对比。音量 25% 不重新开始播放；切换素材会从头播放。25% 指线性音频幅度（约 −12 dB），不是系统音量滑块的 25%。

网络 MP4 使用 [W3C 托管的 Sintel 预告片](https://media.w3.org/2010/05/sintel/trailer.mp4)，作者为 Blender Foundation；不随库打包，公网可用性由其托管服务决定。

旧 PLPlayerKit 适配器保留为可选历史示例：`VIDEOPLAYER_ENABLE_PL=1 pod install`。其旧二进制只适合支持的真机环境，默认与模拟器均不编译该实现；其内部生命周期与协议适配没有纳入本轮可靠性保证。

2026-10-27 基线 iPhone 16e / iOS 27.0.1 真机完整回归 **97 项通过、0 失败、0 跳过**。覆盖本地/HTTP 倍率与媒体时钟、暂停目标展示、锁屏元数据刷新、诊断导航返回，以及既有播放、seek、网络、视频输出和 PiP 委托链路；真实系统 PiP 的本轮验证范围另见记录。

当前 SDK 的 DemoTests 最低 iOS 17（XCTest 运行库限制），不改变 Demo 的 iOS 15 部署版本。执行 DemoTests，详细覆盖、命令和限制见 [测试说明](Demo/Tests/README.md) 与 [真机验证记录](Demo/Tests/DEVICE-VALIDATION.md)。夹具随仓库提供，不依赖公网视频可用性；生成脚本需 ffmpeg，日常测试不需要。

## License

[MIT](LICENSE)

## 本地 podspec 校验

```sh
pod lib lint VideoPlayer.podspec --quick
pod lib lint VideoPlayer.podspec --platforms=ios
```

快速校验检查声明与文件配置，不替代编译。完整 lint 会按 podspec 的 iOS 12 部署目标构建；请通过 `DEVELOPER_DIR` 选择支持 iOS 12 的 Xcode。Xcode 27 下可将 lint 生成的临时验证工程以 `IPHONEOS_DEPLOYMENT_TARGET=15.0` 覆盖构建来检查当前 SDK 的集成，但这不能作为 iOS 12 兼容性验证，也不应为通过 lint 在 podspec 中强制覆盖宿主构建设置。

2026-10-29 Castbox 迁移修改的当前源码已完成 iPhone 16e / iOS 27.0.1 真机完整回归 **105 通过、0 失败、0 跳过**，约 201 秒（含两分钟实际播放）。最小修改、公开接口、回归证据及未验证项见 [迁移验证报告](Demo/Tests/Validation/2026-10-29-castbox-sdk.md)。
