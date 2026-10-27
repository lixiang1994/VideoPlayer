# DemoTests

测试通过 Demo 宿主运行 AVPlayer，使用仓库内的低分辨率生成视频和本机 Network HTTP 服务。默认串行执行，避免系统媒体会话、Now Playing 与网络故障注入互相污染。DemoTests 不依赖 PLPlayerKit 或公网 Apple 示例视频。

## 运行

```sh
cd Demo
pod install
xcodebuild test -workspace Demo.xcworkspace -scheme Demo \
  -destination 'platform=iOS,id=<设备 UDID>' \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/VideoPlayer-tests.xcresult
```

也可使用模拟器 destination，但模拟器的解码、缓冲和 PiP 行为不能替代真机。当前 SDK 的 XCTest 运行库要求测试工程最低 iOS 17（Demo 仍是 iOS 15）；在 Xcode 中选择 Demo scheme 后 Command-U。耗时包含两分钟真实连续播放，不能为加速测试而跳过后仍宣称全量通过。

## 覆盖

| 测试组 | 关注点 |
| --- | --- |
| PlaybackTests | 自动播放、暂停、倍速、循环、重播、有限时间与速率、40 轮资源切换、释放、两分钟实际媒体推进；mix 快照、音轨身份、动态更新与清理 |
| SeekLifecycleTests | 准备期 seek、覆盖、停止、销毁、失败、迟到 completion、多代理同步重入 |
| HTTPPlaybackTests | 视频 MP4、MP3、音频 HLS；Range、重定向、HTTP 错误、延迟、真实缓冲耗尽、暂停后恢复和动态视频 mix |
| SessionAndRemoteTests | 中断 shouldResume、后台许可、用户暂停、输出设备断开、服务重置、锁屏暂停速率与元数据 |
| VideoOutputTests | 真实 PCM 试听电平与离线 mix 衰减、稳定 layer/view、布局、真实帧、无音轨、旋转、MOV/HEVC、纯音频清旧帧、视频 HLS seek、真实视频缓冲耗尽恢复；PiP 桥接与恢复竞争 |
| DemoIntegrationTests | 真实页面控件、播放/暂停时 mix、格式与显示模式、截图、异步准备销毁、旧 mix 取消、网络 HLS 明确禁用与 MP4/HLS 切换清理 |

状态与 seek 的精确竞争使用 ControlledPlayer，资源准备仍由真实 AVPlayer 执行；视频专项还检查像素尺寸和真实图片，避免仅以 control == playing 判断解码成功。本机 HTTP 服务的 suspended 会真正停止供数，测试等待 AVPlayerItemPlaybackStalled，而非自行发通知冒充断流。

系统中断、route change、后台策略的单元测试通过通知验证应用处理策略；它们**没有触发真实来电、耳机拔插或进入后台**。PiP 委托测试也只验证桥接，不证明系统已成功显示 PiP。真实设备事件另见 [DEVICE-VALIDATION.md](DEVICE-VALIDATION.md)。

## 夹具

Fixtures 包含 MP4/MOV/H.264/AAC、HEVC、无音轨、带 90° display matrix 的竖拍、短视频、180 秒长视频以及音频/视频 HLS。样本约 5 MB。默认 MP4 及派生 MOV/HEVC/竖拍含可清楚试听的测试音，平均约 −15 dBFS；180 秒长视频继续保留低振幅，减少长时自动化播放干扰。“无音轨”视频专门验证静音资源，不用于音量对比。生成视频使用 `./generate-media.sh`，需 ffmpeg；日常运行无需 ffmpeg。

竖拍样本使用输入 `-display_rotation:v:0 90` 写入真实旋转矩阵；不要仅写不生效的 rotate 字符串元数据。重建后可使用 ffprobe 检查 Display Matrix。已有音频夹具单独保留，不由视频生成脚本覆盖。

## 真机 PiP 诊断入口

Debug scheme 的环境变量 `VIDEO_DEVICE_DIAGNOSTICS=1` 会直接打开同一个本地播放页并播放 180 秒视频，在系统允许后请求一次 PiP。正常启动不启用该入口；Release 不编译诊断器。

Documents/video-diagnostics.json 记录真实媒体时间、layer.readyForDisplay、实际截图尺寸、PiP possible/active/错误与 UIApplication 前后台事件时刻。通过 devicectl 切到其他 App 再返回可以检查真实生命周期；不能仅因 pipRequested 为 true 就宣称成功。诊断可能占用声卡和显示 PiP，结束后终止应用并普通启动恢复列表。

## 不覆盖的范围

所有容器/profile/码率组合、老系统矩阵、直播滑动窗口、DRM、HDR 色彩、CDN/TLS/鉴权策略、数小时内存与耗电、真实来电/蓝牙/AirPlay、PiP 所有系统交互以及旧 PL 后端不属于自动回归的全面保证。网络 mix 测试验证同 item 配置与播放保持，不是对任意 PCM tap 算法的听感或增益测量。
