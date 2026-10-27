# 真机验证记录

日期：2026-10-27。Xcode 27.0（27A266a），iPhone 16e，iOS 27.0.1（24A446）。默认 AVPlayer 后端，未安装 PLPlayerKit；测试串行执行。库 podspec 现声明最低 iOS 12，旧系统未由这台设备验证。

## 自动化结果

**91 个不同用例通过，最终相关测试均为 0 失败、0 跳过。** 不是把多次重复执行相加后的用例数。

| 运行 | 结果 | 说明 |
| --- | --- | --- |
| full-final | 90 / 90 通过 | 4 页面、16 HTTP、31 播放、16 seek、10 会话/遥控、13 视频输出；含真实两分钟连续视频 |
| review-regression | 15 / 15 通过 | 新增迟到 PiP 恢复关闭用例后，复验 14 视频输出与 1 倍速边界；与前轮合并为 91 个不同用例 |
| scene-pip-final | 18 / 18 通过 | 最终 Scene 生命周期与 PiP 调整后，复验全部 14 视频输出和 4 页面测试 |

机器可读的核对结果：[test-summary.json](Validation/2026-10-27/test-summary.json)。原始 xcresult 保存在本机 `/private/tmp/videoplayer-update/full-final.xcresult`、`review-regression.xcresult`、`scene-pip-final.xcresult`，临时目录可能由系统清理。

首次回归发现并修复了：Demo 缺失 Scene 导致当前 SDK 启动终止、测试 target 产品名配置、竖拍夹具没有实际旋转矩阵、截图同步读取属性阻塞风险、页面 URL 资源无法获得 mix 所需 asset、锁屏暂停速率类型不一致。后续复核修复 PiP 停止事件误转发、恢复 UI 虚报成功、迟到恢复结果污染新控制器，以及前台折叠的生命周期处理（后续按实际体验反馈移除了自动折叠）。

三轮检查分别关注核心状态/取消/代理重入、视频输出/截图/PiP/页面所有权、工程/测试/文档兼容；发现问题后进行了上述相关回归。检查和测试不构成对所有系统状态的无缺陷保证。

## 真实系统 PiP 与后台事件

通过 Debug 环境变量 `VIDEO_DEVICE_DIAGNOSTICS=1`，在真实 Demo 本地页播放 180 秒 H.264/AAC 视频。使用 devicectl 激活系统设置，然后返回 Demo；没有通过 post notification 模拟后台。

最终版本的实测数据：

| 观察点 | 媒体位置 | 系统状态 |
| --- | --- | --- |
| 首次前台采样 | 17.68 秒 | layer.readyForDisplay=true，实际截图 160×90 |
| 真正进入后台 | 19.69 秒 | UIApplicationDidEnterBackground，PiP=true |
| 后台采样 | 57.18 秒 | control=playing，PiP=true，Scene=background |
| 收到返回前台事件 | 57.50 秒 | PiP=true，约 37.80 秒后台墙钟对应约 37.80 秒媒体推进 |
| 返回后采样 | 84.18 秒 | 媒体继续推进；Scene 仍是 foregroundInactive |

保存的原始诊断快照：[前台](Validation/2026-10-27/scene-foreground.json)、[后台](Validation/2026-10-27/scene-background.json)、[返回](Validation/2026-10-27/scene-return.json)。PiP 活动期间内联 layer.readyForDisplay=false 不代表停止解码，画面已由系统接管。

**已确认：真实视频解码、真实系统 PiP 开启、后台持续播放、返回命令后进度保持。**

**尚未确认：用户点击 PiP 恢复/关闭按钮，以及完整导航恢复。** 这次 devicectl 返回后只到 foregroundInactive，没有收到随后的 UISceneDidActivate，因此没有把返回事件冒充完整界面恢复。后续使用反馈发现 Scene 激活会使新开启的 PiP 延迟收回，因此已移除自动折叠。当前不会因应用或 Scene 回前台而主动关闭 PiP，收起交给用户操作。

首次在 foregroundInactive 时主动请求 PiP 被系统拒绝，随后真正进入后台时系统自动 PiP 成功；诊断记录明确区分 requested 与 active，成功后清除旧错误。这不支持“任意时刻程序调用 start 都会成功”的结论。

## 构建与普通启动

- Demo 默认依赖配置在真机编译、签名、安装与测试成功。
- iPhone 18 Pro / iOS 27.0 模拟器上默认 Demo 构建、安装、普通启动及首页截图确认通过；没有据此替代真机解码和 PiP 结果。
- 独立 VideoPlayer framework 的模拟器 Debug、最终源码 Release 构建通过；使用当前 SDK 支持的 iOS 15 构建设置覆盖旧工程部署值。
- 当前 SDK 的 XCTest 运行库最低 iOS 17，因此仅 DemoTests 提高到 iOS 17；Demo 仍为 iOS 15，库 podspec 现声明 iOS 12。
- plist / Podfile / podspec 语法与 git diff --check 通过。部分旧 Demo UIKit 动画 API 有弃用提示，未阻塞构建；未为消除提示而整体重写界面。

## 仍需外部条件的验证

真实电话/系统中断的完整交互、蓝牙拔插与切换、AirPlay、锁屏交互、PiP 全部按钮及多 App 竞争、直播、DRM/HDR、iOS 12–26 设备矩阵、数小时内存/耗电和所有 CDN 编码组合均未完成。会话/路由通知测试只验证应用策略，不代表完成这些系统交互。网络 mix 验证配置、同 item 与媒体推进，不包含任意 tap 算法的 PCM 测量和听感验收。

旧 PLPlayerKit 后端只保留可选历史示例，不在本轮稳定性、模拟器或播放兼容结论内。

## PiP 延迟收回修复

后续使用反馈：开启 PiP 几秒后自动恢复内联播放。代码检查定位到 Scene 激活后延迟 1 秒执行 stopPictureInPicture 的策略；Scene 激活不能可靠区分用户恢复页面与 PiP 自身转场。已删除该监听和延迟任务，保留显式收起、关闭、资源结束清理以及系统恢复 UI 委托。此前后台连续播放数据仍有效，不代表已实测全部 PiP 按钮交互。

删除自动折叠后，真机 VideoOutputTests 14 项全部通过，0 失败、0 跳过，结果包为 `/private/tmp/videoplayer-update/pip-no-autostop.xcresult`。该回归包含截图、格式、视频网络与 PiP 委托/释放逻辑；未据此宣称所有系统按钮交互已实测。

## 网络页 HLS 音量 mix 无效修复

用户反馈网络视频的“音量 25%”没有效果，确认使用的是默认 HLS 示例。该资源不支持此 AVAudioMix 音量处理路径；此前只确认 item 接受配置与进度保持，不能证明 HLS 的实际输出音量变化。

网络页现在明确分为 HLS（禁用 mix 并持续显示原因）与普通 HTTPS MP4（可测试 mix），不通过替换成 player.volume 来冒充音轨处理。新增网络页 HLS 提示、普通 HTTP MP4 提交后保留 item/进度、切回真实视频 HLS 清除 mix 的页面测试。与原有页面及 HTTP mix 测试合并的 7 项真机回归全部通过，0 失败、0 跳过；结果包 `/private/tmp/videoplayer-update/mix-hls-compatibility.xcresult`。新增 2 个不同用例后，累计已验证 93 个不同用例。

公网 MP4 地址 HEAD 验证返回 200、video/mp4、Accept-Ranges: bytes；自动化仍使用本机 HTTP 服务，不依赖公网样本。此次没有测量扬声器声压或录制系统实际输出 PCM，因此不把配置检查描述为音量听感验收。

## 本地试听素材音量过低修复

用户反馈本地视频听不到声音。检查样本确实含 AAC 音轨，但 ffmpeg sine 原本已有较低幅度，生成脚本又乘以 0.02，解码平均电平约 −55.1 dBFS，无法有效试听。现将默认 24 秒样本的生成增益改为 2，并重建 MP4、MOV、HEVC、竖拍和视频 HLS 派生样本；无音轨案例仍无音轨，180 秒长视频仍保留低振幅。

重建后的主样本平均电平约 −15.1 dBFS，AAC 解码峰值约 −9.2 dBFS；在主机上额外施加 0.25 增益后的平均电平约 −27.1 dBFS。默认本地按钮标为“MP4 有声”。

新增真机 testLocalAudioLevelAndMixAttenuation：实际 AVAssetReader 解码样本，要求原始 RMS 高于 0.05（约 −26 dBFS）；使用 AVAssetReaderAudioMixOutput 应用 AVAudioMix 后，要求 RMS 比例为 0.25 ± 0.01。该检查验证素材与离线 mix 的真实 PCM，不冒充扬声器声压、实时 AVPlayer 输出或人工听感。

更新素材后，全部页面、HTTP 和视频输出回归共 37 项真机测试通过，0 失败、0 跳过；结果包 `/private/tmp/videoplayer-update/audible-local-fixtures.xcresult`。累计已验证 94 个不同用例。测试机已重新安装含新素材的 Demo 并恢复普通启动。


## 通用修复同步（2026-10-27）

对照 AudioPlayer 当前实现检查核心状态、seek 取消、代理重入、会话中断、资源切换与动态 audioMix；对应通用逻辑已具备，不复制视频/音频之间有意不同的输出与后台接口，也不加入静音加速、PCM 检测或其缓冲能力接口。

本轮修复：

- `VideoPlayerRemoteControl.set(...)` 替换元数据后立即补回当前进度、时长、执行速率与默认目标速率；播放中和暂停时都回归。只有资源就绪且控制状态为播放时，锁屏速率才为目标值，其余为 0。
- Demo 倍率明确标为目标；暂停时修改选择立即刷新，准备、缓冲、结束与失败单独展示，不等待媒体进度回调。
- 真机诊断入口保留 storyboard 列表及返回按钮，独立窗口也补齐相同导航；返回清理视频。默认仍请求系统 PiP，导航测试通过独立参数关闭主动请求，不把导航回归当作系统 PiP 开启验证。

新增 3 项测试：导航栈/返回停止，本地与 HTTP MP4 的目标文案及实际媒体时钟，播放/暂停中更新锁屏元数据。当前共 **97 项**：Playback 31、Seek 16、HTTP 16、Session 11、VideoOutput 15、Demo 8。两分钟播放新增被动系统中断与前后台诊断附件，保留原有每十秒推进断言。

iPhone 16e / iOS 27.0.1 最终完整一轮 **97 通过、0 失败、0 跳过**，约 201 秒。两分钟媒体推进至 120.26 秒，该轮附件没有中断或退后台。本地及 HTTP 的底层速率与 1.5×/2× 目标一致；独立媒体时钟测量分别为本地 1.500/2.186×、HTTP 1.500/2.000×，均在测试允许的 ±0.25× 短窗口调度/切速误差内。这是短区间推进验证，不声称逐帧精确测速。

第一轮两项针对性测试中，导航起播曾在 8 秒内超时；增加状态附件并使用 15 秒异步加载上限后，3 项针对性测试全部通过，最终完整回归也通过。没有证据确定首次超时原因，未将它当作通过；返回停止、导航与媒体推进断言未放宽。

复查本轮全部改动及相关调用链，未发现新的可确认问题。工程文件、podspec 语法和 diff 检查通过；没有修改版本、tag 或发布配置。本轮未重复触发真实系统 PiP/来电/蓝牙/AirPlay，相关既有证据与限制仍以上文为准。

[97 项真机结果](/private/tmp/videoplayer-common-full.xcresult) · [日志](/private/tmp/videoplayer-common-full.log) · [测量及中断附件](/private/tmp/videoplayer-common-attachments/manifest.json)

[首次针对性结果](/private/tmp/videoplayer-common-targeted.xcresult) · [3 项针对性复测](/private/tmp/videoplayer-common-targeted2.xcresult)
