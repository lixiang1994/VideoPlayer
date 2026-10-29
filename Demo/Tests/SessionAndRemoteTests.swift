import XCTest
import AVFoundation
import MediaPlayer
import UIKit
@testable import VideoPlayer

/// 使用系统通知验证中断策略，锁屏速率必须反映实际播放状态。
final class SessionAndRemoteTests: PlaybackTestCase {
    /// 宿主接管时三类会话通知均无 SDK 副作用，重准备不会重新开启监听。
    func testHostCanDisableAudioSessionNotifications() {
        XCTAssertTrue(VideoPlayerConfiguration().handlesAudioSessionNotifications)
        engine.stop()
        var configuration = VideoPlayerConfiguration()
        configuration.isAutoplay = false
        configuration.handlesAudioSessionNotifications = false
        engine = AVVideoPlayer(configuration)
        engine.add(delegate: recorder)
        for url in [audio, otherAudio] {
            prepare(url)
            engine.play()
            eventually("先开始播放") { self.engine.nativePlaybackSample.rate > 0 }
            interruption(.began)
            pump(0.1)
            XCTAssertEqual(engine.control, .playing)
            XCTAssertGreaterThan(engine.nativePlaybackSample.rate, 0)
            interruption(.ended) // 没有 shouldResume 也不能撤销宿主的播放意图。
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
            pump(0.1)
            XCTAssertEqual(engine.control, .playing)
            NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification,
                object: AVAudioSession.sharedInstance())
            pump(0.1)
            XCTAssertEqual(engine.resource?.value, url)
            if case .playing = engine.state {} else { XCTFail("关闭监听后不能失败") }
            XCTAssertGreaterThan(engine.nativePlaybackSample.rate, 0)
            engine.pause()
            XCTAssertEqual(engine.nativePlaybackSample.rate, 0)
        }
        engine.allowedBackgroundPlayback = false
        engine.play()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertEqual(engine.nativePlaybackSample.rate, 0)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        eventually("App 前后台策略仍应生效") { self.engine.control == .playing }
    }

    /// 系统 timeControlStatus 迟到仍为 playing 时，后台策略也不能向业务层报告正在播放。
    func testBackgroundPolicyOverridesStaleSystemPlayingStatus() {
        engine.stop()
        var configuration = VideoPlayerConfiguration()
        configuration.isAutoplay = false
        engine = AVVideoPlayer(configuration, player: StalePlayingStatusPlayer())
        prepare()
        engine.allowedBackgroundPlayback = false
        engine.play()
        XCTAssertEqual(engine.control, .playing)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(engine.control, .pausing)
        engine.play()
        XCTAssertEqual(engine.control, .pausing)
    }

    /// 禁止后台播放时，进入后台暂停，回到前台应恢复此前保留的播放意图。
    func testForegroundRestoresPlaybackBlockedByBackgroundPolicy() {
        prepare()
        engine.allowedBackgroundPlayback = false
        engine.play()
        eventually("先开始播放") { self.engine.control == .playing }
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        eventually("进入后台应暂停") { self.engine.control == .pausing }
        // 在后台再次请求播放也必须受策略约束，不能只在通知到达时暂停一次。
        engine.play()
        pump(0.1)
        XCTAssertEqual(engine.control, .pausing)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        eventually("回前台应恢复原播放意图") { self.engine.control == .playing }
    }

    /// 后台主动暂停会撤销播放意图，回前台不得自动恢复。
    func testUserPauseInBackgroundPreventsForegroundResume() {
        prepare()
        engine.allowedBackgroundPlayback = false
        engine.play()
        eventually("先开始播放") { self.engine.control == .playing }
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        engine.pause()
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        pump(0.1)
        XCTAssertEqual(engine.control, .pausing)
    }

    /// 无恢复许可时，即使中断前在播放也必须保持暂停。
    func testInterruptionWithoutResumePermissionStaysPaused() {
        prepare()
        engine.play()
        eventually("先开始播放") { self.engine.control == .playing }
        interruption(.began)
        eventually("中断应暂停") { self.engine.control == .pausing }
        interruption(.ended)
        pump(0.1)
        XCTAssertEqual(engine.control, .pausing)
        let current = engine.current
        pump(0.1)
        XCTAssertEqual(engine.current, current, accuracy: 0.05)
    }
    
    /// 有恢复许可且用户没有暂停时，保留的意图应恢复播放。
    func testInterruptionWithPermissionResumes() {
        prepare()
        engine.play()
        eventually("先开始播放") { self.engine.control == .playing }
        interruption(.began)
        eventually("中断应暂停") { self.engine.control == .pausing }
        interruption(.ended, options: .shouldResume)
        eventually("系统许可后应恢复") { self.engine.control == .playing }
    }
    
    /// 中断期间切资源也不能清掉会话中断标记，需等到系统许可才能起播。
    func testPrepareDuringInterruptionWaitsForResume() {
        prepare()
        interruption(.began)
        pump(0.03)
        prepare(otherAudio)
        engine.play()
        pump(0.1)
        XCTAssertEqual(engine.control, .pausing)
        interruption(.ended, options: .shouldResume)
        eventually("新资源应在许可后恢复") { self.engine.control == .playing }
    }
    
    /// 用户在中断期间主动暂停，系统许可也不能覆盖用户操作。
    func testUserPauseDuringInterruptionPreventsResume() {
        prepare()
        engine.play()
        eventually("先开始播放") { self.engine.control == .playing }
        interruption(.began)
        eventually("中断应暂停") { self.engine.control == .pausing }
        engine.pause()
        interruption(.ended, options: .shouldResume)
        pump(0.15)
        XCTAssertEqual(engine.control, .pausing)
    }
    
    /// 已断开的耳机或蓝牙输出不再可用时，应撤销播放意图。
    func testOldDeviceUnavailablePauses() {
        prepare()
        engine.play()
        eventually("先开始播放") { self.engine.control == .playing }
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        eventually("输出设备断开应暂停") { self.engine.control == .pausing }
    }
    
    /// 音频服务重置不能假装继续播放，应暴露失败并允许业务重建会话。
    func testMediaServicesResetReportsFailure() {
        prepare()
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: AVAudioSession.sharedInstance())
        eventually("服务重置应失败") { if case .failed = self.engine.state { return true }; return false }
        XCTAssertNil(engine.resource)
    }
    
    /// 锁屏暂停速率为零，默认速率保留用户设置，并保留标题等元数据。
    func testNowPlayingRateTracksPauseAndResume() {
        prepare()
        let remote = VideoPlayerRemoteControl(engine)
        remote.set(title: "测试单集", artist: "测试作者", thumb: UIImage(), url: audio)
        engine.rate = 1.5
        engine.play()
        eventually("先开始播放") { self.engine.control == .playing }
        remote.updatePlayingInfo()
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo!
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.5)
        engine.pause()
        info = MPNowPlayingInfoCenter.default().nowPlayingInfo!
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? Double, 1.5)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "测试单集")
        remote.cleanPlayingInfo()
    }
    
    /// 播放/暂停期间替换元数据必须立即带上当前进度与速率，不能等下一次周期回调。
    func testReplacingNowPlayingMetadataPreservesClockAndRate() {
        prepare()
        let remote = VideoPlayerRemoteControl(engine)
        defer { remote.cleanPlayingInfo() }
        engine.rate = 1.5
        engine.play()
        eventually("媒体应实际推进") { self.engine.current > 0.3 }
        for paused in [false, true] {
            if paused { engine.pause() }
            remote.set(title: paused ? "暂停后更新" : "播放中更新", artist: "测试作者", thumb: UIImage(), url: audio)
            let info = MPNowPlayingInfoCenter.default().nowPlayingInfo!
            XCTAssertEqual(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, engine.current, accuracy: 0.03)
            XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, paused ? 0 : 1.5)
            XCTAssertEqual(info[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? Double, 1.5)
            XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double ?? -1, engine.duration, accuracy: 0.01)
            XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, paused ? "暂停后更新" : "播放中更新")
        }
    }

    /// 发送与系统格式一致的中断通知，等待由播放器统一回主线程消费。
    private func interruption(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions = []) {
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue, AVAudioSessionInterruptionOptionKey: options.rawValue])
    }
}

/// 确定性模拟暂停后底层状态尚未更新，真实 AVPlayer 仍负责资源加载及控制。
private final class StalePlayingStatusPlayer: AVPlayer {
    override var timeControlStatus: AVPlayer.TimeControlStatus { .playing }
}
