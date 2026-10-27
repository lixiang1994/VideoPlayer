import XCTest
import AVFoundation
import UIKit
@testable import VideoPlayer

/// 验证 Demo 实际使用的 AVPlayer 后端，包括暂停、倍速、准备阶段恢复进度和错误恢复。
final class PlaybackTests: PlaybackTestCase {

    /// 更新当前 mix 不能换 item、重置时间或改变控制状态；nil 可恢复默认处理。
    func testLiveAudioMixUpdatePreservesItemAndPlayback() throws {
        let player = useControlledPlayer()
        let asset = AVURLAsset(url: audio)
        engine.prepare(resource: asset)
        engine.play()
        eventually("先实际播放") { self.engine.current > 0.3 }
        let item = try XCTUnwrap(player.currentItem)
        let capability: AVVideoAudioMixControlling = try XCTUnwrap(engine)
        let mix = try makeAudioMix(asset: asset, volume: 0.25)
        for _ in 0..<10 {
            let before = engine.current
            XCTAssertTrue(capability.update(audioMix: mix, for: asset))
            XCTAssertTrue(player.currentItem === item)
            XCTAssertEqual(engine.current, before, accuracy: 0.1)
            XCTAssertEqual(engine.control, .playing)
            XCTAssertNotNil(capability.audioMix)
            XCTAssertTrue(capability.update(audioMix: nil, for: asset))
            XCTAssertNil(capability.audioMix)
        }
        let before = engine.current
        eventually("修改后仍应继续推进") { self.engine.current > before + 0.2 }
    }

    /// 暂停及准备阶段设置 mix 都保留控制意图，修改原始 mutable mix 不影响当前 item。
    func testLiveAudioMixUpdatePreservesPauseAndCopiesConfiguration() throws {
        let player = useControlledPlayer()
        let asset = AVURLAsset(url: audio)
        engine.prepare(resource: asset)
        let mix = try makeAudioMix(asset: asset, volume: 0.25)
        XCTAssertTrue(engine.update(audioMix: mix, for: asset))
        mix.inputParameters = []
        XCTAssertEqual(engine.audioMix?.inputParameters.count, 1)
        pump(0.2)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
        XCTAssertTrue(player.currentItem?.asset === asset)
    }

    /// 旧 asset（即使 URL 相同）、停止后或尚无资源时的更新都应拒绝，不污染下一首。
    func testLiveAudioMixUpdateRejectsStaleAssetAndStoppedResource() throws {
        let player = useControlledPlayer()
        let asset = AVURLAsset(url: audio)
        engine.prepare(resource: asset)
        let mix = try makeAudioMix(asset: asset, volume: 0.25)
        XCTAssertFalse(engine.update(audioMix: mix, for: AVURLAsset(url: audio)))
        XCTAssertNil(engine.audioMix)
        engine.prepare(resource: otherAudio)
        let next = player.currentItem
        XCTAssertFalse(engine.update(audioMix: mix, for: asset))
        XCTAssertTrue(player.currentItem === next)
        XCTAssertNil(engine.audioMix)
        engine.stop()
        XCTAssertFalse(engine.update(audioMix: mix, for: asset))
        XCTAssertNil(engine.audioMix)
        prepare()
        XCTAssertNil(engine.audioMix)
    }

    /// 资源对可变 mix 取快照，提交后修改原配置不能改变资源的音轨参数。
    func testAudioMixResourceCopiesMutableConfiguration() throws {
        let asset = AVURLAsset(url: audio)
        let mix = try makeAudioMix(asset: asset, volume: 0.25)
        let resource = AVVideoPlayerResource(asset: asset, audioMix: mix)
        XCTAssertTrue(resource.asset === asset)
        XCTAssertEqual(resource.value, audio)
        XCTAssertFalse(resource.audioMix === mix)
        mix.inputParameters = []
        XCTAssertEqual(resource.audioMix?.inputParameters.count, 1)
    }

    /// 使用真实音轨创建 mix，必须在播放前绑定到原 asset，准备和实际播放仍正常。
    func testAudioMixResourceUsesOriginalAssetAndPlays() throws {
        let player = useControlledPlayer()
        let asset = AVURLAsset(url: audio)
        let mix = try makeAudioMix(asset: asset, volume: 0.25)
        engine.prepare(resource: AVVideoPlayerResource(asset: asset, audioMix: mix))
        let item = try XCTUnwrap(player.currentItem)
        XCTAssertTrue(item.asset === asset)
        let parameters = try XCTUnwrap(item.audioMix?.inputParameters.first)
        XCTAssertEqual(parameters.trackID, mix.inputParameters.first?.trackID)
        var volume: Float = 0
        var endVolume: Float = 0
        var range = CMTimeRange.zero
        XCTAssertTrue(parameters.getVolumeRamp(for: .zero, startVolume: &volume, endVolume: &endVolume, timeRange: &range))
        XCTAssertEqual(volume, 0.25, accuracy: 0.001)
        engine.play()
        eventually("携带 mix 的资源应实际播放") { self.engine.current > 0.2 }
    }

    /// 每次切资源创建独立 item；新音轨的 mix 不能继续使用上一资源的参数。
    func testAudioMixResourceSwitchReplacesMix() throws {
        let player = useControlledPlayer()
        let first = AVURLAsset(url: audio)
        engine.prepare(resource: AVVideoPlayerResource(asset: first, audioMix: try makeAudioMix(asset: first, volume: 0.25)))
        let oldItem = try XCTUnwrap(player.currentItem)
        let next = AVURLAsset(url: otherAudio)
        engine.prepare(resource: AVVideoPlayerResource(asset: next, audioMix: try makeAudioMix(asset: next, volume: 0.75)))
        XCTAssertFalse(player.currentItem === oldItem)
        XCTAssertTrue(player.currentItem?.asset === next)
        var volume: Float = 0
        var endVolume: Float = 0
        var range = CMTimeRange.zero
        XCTAssertTrue(player.currentItem?.audioMix?.inputParameters.first?.getVolumeRamp(for: .zero, startVolume: &volume, endVolume: &endVolume, timeRange: &range) == true)
        XCTAssertEqual(volume, 0.75, accuracy: 0.001)
    }

    /// 专用资源的 nil mix、普通 URL 与直接 AVURLAsset 都不能继承上一首的 mix。
    func testResourcesWithoutMixClearPreviousMix() throws {
        let player = useControlledPlayer()
        let asset = AVURLAsset(url: audio)
        let mixed = AVVideoPlayerResource(asset: asset, audioMix: try makeAudioMix(asset: asset, volume: 0.25))
        let plain: [VideoPlayerURLAsset] = [AVVideoPlayerResource(asset: asset), otherAudio, asset]
        for resource in plain {
            engine.prepare(resource: mixed)
            XCTAssertNotNil(player.currentItem?.audioMix)
            engine.prepare(resource: resource)
            XCTAssertNil(player.currentItem?.audioMix)
        }
        XCTAssertTrue(player.currentItem?.asset === asset)
    }

    /// 停止会解除引擎对专用资源和 item 的持有，重新播放普通资源不能带回旧配置。
    func testAudioMixResourceStopClearsItemAndResource() throws {
        let player = useControlledPlayer()
        let asset = AVURLAsset(url: audio)
        engine.prepare(resource: AVVideoPlayerResource(asset: asset, audioMix: try makeAudioMix(asset: asset, volume: 0.25)))
        engine.stop()
        XCTAssertNil(player.currentItem)
        XCTAssertNil(engine.resource)
        prepare()
        XCTAssertNil(player.currentItem?.audioMix)
    }

    /// 当前 item 播放失败后，原清理链路同样必须解除专用资源与 mix 的关联。
    func testAudioMixResourceFailureClearsItemAndResource() throws {
        let player = useControlledPlayer()
        let asset = AVURLAsset(url: audio)
        engine.prepare(resource: AVVideoPlayerResource(asset: asset, audioMix: try makeAudioMix(asset: asset, volume: 0.25)))
        let item = try XCTUnwrap(player.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: item)
        eventually("失败应清空当前 item 和资源") { player.currentItem == nil && self.engine.resource == nil }
        prepare()
        XCTAssertNil(player.currentItem?.audioMix)
    }

    /// 仅测试使用同步音轨查询；调用方在生产环境应异步加载音轨后再准备资源。
    private func makeAudioMix(asset: AVURLAsset, volume: Float) throws -> AVMutableAudioMix {
        let track = try XCTUnwrap(asset.tracks(withMediaType: .audio).first)
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.setVolume(volume, at: .zero)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }
    /// 低码率 MP3 使用实际系统解码，向后 seek 后验证实际媒体时间。
    func testMP3PlaybackAndBackwardSeek() {
        let url = Bundle.main.url(forResource: "tone", withExtension: "mp3", subdirectory: "Fixtures")!
        prepare(url, seek: 65)
        engine.seek(to: .init(time: 3))
        eventually("MP3 向后 seek 应完成") { self.recorder.seekEnds.contains(3) }
        XCTAssertEqual(engine.current, 3, accuracy: 0.15)
        engine.play()
        eventually("MP3 应实际推进") { self.engine.current > 3.3 }
    }

    /// 真实后端反复切资源并寻时，检查每次取消 completion、停止和资源释放。
    func testRepeatedResourceSwitchSeekAndStop() {
        for index in 0..<40 {
            engine.prepare(resource: index % 2 == 0 ? audio : otherAudio)
            var result: [Bool] = []
            engine.seek(to: .init(time: 6, completion: { result.append($0) }))
            engine.stop()
            XCTAssertEqual(result, [false])
            XCTAssertNil(engine.resource)
            XCTAssertEqual(engine.current, 0)
            if index % 5 == 0 { pump(0.02) }
        }
        prepare()
        engine.play()
        eventually("多轮取消后仍应正常播放") { self.engine.current > 0.2 }
    }

    /// 多次创建和释放已安装观察者的实例，底层播放器不能反向保留引擎。
    func testRepeatedEngineDeallocation() {
        for _ in 0..<40 {
            autoreleasepool {
                let player = ControlledPlayer()
                var temporary: AVVideoPlayer? = AVVideoPlayer(.init(), player: player)
                weak var weakEngine = temporary
                temporary?.prepare(resource: audio)
                temporary = nil
                XCTAssertNil(weakEngine)
                XCTAssertNil(player.currentItem)
                XCTAssertEqual(player.removedTimeObservers, 1)
            }
        }
        pump(0.1)
    }

    /// 两分钟连续播放烟测，每十秒检查实际推进；这不能替代数小时耗电与内存测试。
    func testTwoMinuteContinuousPlayback() {
        // 保存系统中断与前后台证据；不自动恢复播放，也不放宽连续推进的验收断言。
        let player = engine!
        let start = ProcessInfo.processInfo.systemUptime
        var events: [String] = []
        /// 所有通知与控制回调均在主线程收集，只记录当前测试实例的状态。
        func record(_ event: String) {
            events.append(String(format: "%.3f current=%.3f target=%.1f control=%@ app=%d %@", ProcessInfo.processInfo.systemUptime - start, player.current, player.rate, String(describing: player.control), UIApplication.shared.applicationState.rawValue, event))
        }
        let names: [Notification.Name] = [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification]
        let tokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
                let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                record("\(name.rawValue) type=\(String(describing: type)) options=\(String(describing: options))")
            }
        }
        recorder.onControl = { state in record("control=\(state)") }
        defer {
            recorder.onControl = nil
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            let trace = XCTAttachment(string: events.joined(separator: "\n"))
            trace.name = "两分钟播放的系统中断与生命周期"
            trace.lifetime = .keepAlways
            add(trace)
        }
        record("start")
        let url = Bundle.main.url(forResource: "long", withExtension: "mp4", subdirectory: "Fixtures")!
        prepare(url)
        engine.play()
        eventually("先实际播放") { self.engine.current > 0.2 }
        var previous = engine.current
        for _ in 0..<12 {
            pump(10)
            record("sample")
            XCTAssertEqual(engine.control, .playing)
            XCTAssertGreaterThan(engine.current - previous, 8)
            previous = engine.current
        }
        XCTAssertGreaterThan(engine.current, 118)
    }

    /// 禁止自动播放时，ready 后也不能偷偷推进播放进度。
    func testPrepareWithoutAutoplayRemainsPaused() {
        prepare()
        pump(0.3)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
    }
    
    /// 默认自动播放应在准备完成后实际推进时间。
    func testAutoplayAdvancesActualTime() {
        engine.stop()
        engine = AVVideoPlayer(.init())
        engine.prepare(resource: audio)
        eventually("自动播放应实际推进") { self.engine.current > 0.15 }
        XCTAssertEqual(engine.control, .playing)
    }
    
    /// 暂停、修改倍速、恢复不能丢失暂停意图或起播位置。
    func testPauseRateAndResume() {
        prepare()
        engine.play()
        eventually("播放应推进") { self.engine.current > 0.15 }
        engine.pause()
        pump(0.05)
        let current = engine.current
        engine.rate = 1.5
        pump(0.2)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertEqual(engine.current, current, accuracy: 0.06)
        engine.play()
        eventually("恢复应继续推进") { self.engine.current > current + 0.15 }
    }
    
    /// Demo 在 prepare 后立即恢复播放记录，必须等待真正寻时完成且保持暂停。
    func testSeekBeforeReady() {
        prepare(seek: 8)
        pump(0.1)
        XCTAssertEqual(engine.current, 8, accuracy: 0.1)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertFalse(recorder.receivedOffMain)
    }
    
    /// 快速重复拖动应落在最后目标，而不是只返回乐观进度。
    func testRapidSeeksReachLastPosition() {
        prepare()
        engine.seek(to: .init(time: 4))
        engine.seek(to: .init(time: 12))
        engine.seek(to: .init(time: 6))
        eventually("最后一次寻时应完成") { self.recorder.seekEnds.contains(6) }
        pump(0.1)
        XCTAssertEqual(engine.current, 6, accuracy: 0.1)
        XCTAssertEqual(engine.control, .pausing)
    }
    
    /// 寻时期间收到暂停，完成后不得自动恢复。
    func testPauseDuringSeek() {
        prepare()
        engine.play()
        recorder.onSeekBegan = { self.engine.pause() }
        engine.seek(to: .init(time: 10))
        eventually("寻时应完成") { self.recorder.seekEnds.contains(10) }
        pump(0.15)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertEqual(engine.current, 10, accuracy: 0.1)
    }
    
    /// 向前或向后 seek 完成后切资源，不应保留旧资源的校准进度。
    func testNewResourceClearsSeekCalibration() {
        prepare()
        engine.seek(to: .init(time: 18))
        eventually("先完成旧资源寻时") { self.recorder.seekEnds.contains(18) }
        prepare(otherAudio)
        pump(0.1)
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
        XCTAssertEqual(engine.resource?.value, otherAudio)
    }
    
    /// 同 URL 重载同样是新资源，旧进度和请求必须全部失效。
    func testSameURLReloadStartsAtZero() {
        prepare(seek: 9)
        prepare(audio)
        pump(0.1)
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
    }
    
    /// 非法时间应以失败结束，不能留下永远无法消费的 seek 意图。
    func testInvalidAndStoppedSeekCompleteFalse() {
        var results: [Bool] = []
        engine.seek(to: .init(time: 2, completion: { results.append($0) }))
        prepare()
        engine.seek(to: .init(time: .nan, completion: { results.append($0) }))
        engine.seek(to: .init(time: .infinity, completion: { results.append($0) }))
        XCTAssertEqual(results, [false, false, false])
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
    }
    
    /// 负数目标限制在零，不应在失败时保留负数校准值。
    func testNegativeSeekClampsToStart() {
        prepare(seek: 8)
        engine.seek(to: .init(time: -5))
        eventually("负数寻时应结束") { self.recorder.seekEnds.contains(-5) }
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
    }
    
    /// 自然结束后再次 play，应实际从头播放。
    func testFinishAndReplay() {
        prepare(PlaybackFixtures.shortAudio)
        engine.play()
        eventually("短音频应自然结束") { if case .finished = self.engine.state { return true }; return false }
        engine.play()
        eventually("重播应恢复出声状态") { self.engine.control == .playing && self.engine.current > 0.05 && self.engine.current < 0.5 }
    }
    
    /// 单曲循环依靠真实结束事件恢复，不能停在 finished。
    func testLoopRestartsPlayback() {
        prepare(PlaybackFixtures.shortAudio)
        engine.isLoop = true
        engine.play()
        eventually("循环应至少触发一次回到起点的 seek") { self.recorder.seekEnds.contains(0) }
        eventually("循环后应继续播放") { self.engine.control == .playing }
    }
    
    /// 失败后允许重新准备正常资源，不残留失败状态。
    func testFailureThenPrepareValidResource() {
        engine.prepare(resource: URL(fileURLWithPath: "/does-not-exist/audio.wav"))
        eventually("无效资源应失败") { if case .failed = self.engine.state { return true }; return false }
        prepare()
        engine.play()
        eventually("失败恢复后应正常推进") { self.engine.current > 0.1 }
    }
    
    /// 本地 AAC 文件验证系统压缩格式解码和向后 seek。
    func testCompressedAudioAndBackwardSeek() {
        prepare(PlaybackFixtures.compressedAudio, seek: 14)
        engine.seek(to: .init(time: 3))
        eventually("向后寻时应完成") { self.recorder.seekEnds.contains(3) }
        XCTAssertEqual(engine.current, 3, accuracy: 0.1)
    }
    
    /// NaN、无穷与无法转换为 Float 的倍速不能传入 AVPlayer。
    func testInvalidRatePreservesPreviousSetting() {
        engine.rate = 1.5
        for value in [Double.nan, Double.infinity, Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude, 0, -1] {
            engine.rate = value
            XCTAssertEqual(engine.rate, 1.5)
        }
    }
    
    /// 已结束资源可先设置新的目标，再 play；同一个业务 completion 不应先取消再成功。
    func testSeekAfterFinishCompletesOnceWhenReplayed() {
        prepare(PlaybackFixtures.shortAudio)
        engine.play()
        eventually("先等待结束") { if case .finished = self.engine.state { return true }; return false }
        var results: [Bool] = []
        engine.seek(to: .init(time: 0.1, completion: { results.append($0) }))
        engine.play()
        eventually("重播应完成待处理寻时") { !results.isEmpty }
        pump(0.05)
        XCTAssertEqual(results, [true])
    }
    
    /// ready 后的播放失败通知必须携带原始错误进入 failed，随后释放资源。
    func testFailureToEndPreservesUnderlyingError() {
        engine.stop()
        let player = ControlledPlayer()
        engine = AVVideoPlayer(.init(), player: player)
        prepare()
        let error = NSError(domain: "VideoPlayer.Tests", code: 123)
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: player.currentItem!, userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: error])
        eventually("播放中失败应被消费") { if case .failed = self.engine.state { return true }; return false }
        if case .failed(let actual) = engine.state {
            XCTAssertEqual((actual as NSError?)?.domain, error.domain)
            XCTAssertEqual((actual as NSError?)?.code, error.code)
        }
        XCTAssertNil(engine.resource)
    }
    
    /// 零回调频率不能构造无效 timescale 或让播放器崩溃。
    func testZeroCallbackFrequencyIsSafe() {
        engine.stop()
        var configuration = VideoPlayerConfiguration()
        configuration.currentTimeCallbackPeriodicInterval = 0
        engine = AVVideoPlayer(configuration)
        engine.prepare(resource: audio)
        eventually("无效频率应安全降为每秒一次") { self.engine.current > 0.1 }
    }
}
