import XCTest
import AVFoundation
import AVKit
@testable import VideoPlayer
@testable import Demo

/// 视频专用回归使用真实 H.264 / HEVC 解码和画面输出，避免把音频时钟推进当作画面正确。
final class VideoOutputTests: PlaybackTestCase {
    /// 解码真实样本检查电平，避免“有音轨但几乎无声”；通过离线 mix 输出验证 25% 确实衰减 PCM。
    /// 这里验证素材与音量包络，不把离线处理冒充设备扬声器或实时 AVPlayer 的听感测量。
    func testLocalAudioLevelAndMixAttenuation() throws {
        let asset = AVURLAsset(url: audio)
        let tracks = asset.tracks(withMediaType: .audio)
        XCTAssertFalse(tracks.isEmpty)
        let original = try decodedAudioRMS(asset: asset, tracks: tracks, volume: 1)
        let reduced = try decodedAudioRMS(asset: asset, tracks: tracks, volume: 0.25)
        XCTAssertGreaterThan(original, 0.05, "试听素材平均电平应高于约 -26 dBFS，不能再次生成接近无声的音轨")
        XCTAssertLessThan(original, 0.4, "测试音不应接近满幅")
        XCTAssertEqual(reduced / original, 0.25, accuracy: 0.01)
    }

    /// 只解码开头一秒浮点 PCM；分块累计能量，避免为电平检查读取整段视频或保留全部采样。
    private func decodedAudioRMS(asset: AVURLAsset, tracks: [AVAssetTrack], volume: Float) throws -> Double {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1
        ])
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.map {
            let parameter = AVMutableAudioMixInputParameters(track: $0)
            parameter.setVolume(volume, at: .zero)
            return parameter
        }
        output.audioMix = mix
        reader.add(output)
        guard reader.startReading() else { throw try XCTUnwrap(reader.error) }
        defer { reader.cancelReading() }
        var energy: Double = 0
        var count = 0
        while count < 44100, let sample = output.copyNextSampleBuffer() {
            let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample))
            let length = CMBlockBufferGetDataLength(block)
            var values = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = values.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            XCTAssertEqual(status, kCMBlockBufferNoErr)
            for value in values { energy += Double(value) * Double(value) }
            count += values.count
        }
        XCTAssertGreaterThan(count, 0)
        if reader.status == .failed { throw try XCTUnwrap(reader.error) }
        return count > 0 ? sqrt(energy / Double(count)) : 0
    }

    /// 真实 PiP 桥接停止事件只能转发 didStop，不能误发 willStart；此处验证委托逻辑，不冒充系统开启 PiP。
    func testPiPStopForwardsCorrectEvent() throws {
        let wrapper = PictureInPicture()
        wrapper.setup(player: AVPlayerLayer())
        let controller = try XCTUnwrap(wrapper.pictureController)
        let spy = PiPDelegateRecorder()
        wrapper.delegate = spy
        wrapper.pictureInPictureControllerDidStopPictureInPicture(controller)
        XCTAssertEqual(spy.stops, 1)
        XCTAssertEqual(spy.starts, 0)
        wrapper.close()
        wrapper.pictureInPictureControllerDidStopPictureInPicture(controller)
        XCTAssertEqual(spy.stops, 1)
    }

    /// UI 恢复结果由界面持有者提供；没有委托或旧控制器事件必须回 false。
    func testPiPRestoreUsesDelegateResult() throws {
        let wrapper = PictureInPicture()
        wrapper.setup(player: AVPlayerLayer())
        let controller = try XCTUnwrap(wrapper.pictureController)
        var results: [Bool] = []
        wrapper.pictureInPictureController(controller, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler: { results.append($0) })
        let spy = PiPDelegateRecorder()
        wrapper.delegate = spy
        spy.canRestore = true
        wrapper.pictureInPictureController(controller, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler: { results.append($0) })
        wrapper.close()
        wrapper.pictureInPictureController(controller, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler: { results.append($0) })
        XCTAssertEqual(results, [false, true, false])
    }

    /// 宿主异步恢复完成前关闭 PiP，迟到的成功结果不得污染新的控制器生命周期。
    func testPiPDelayedRestoreAfterCloseReturnsFalse() throws {
        let wrapper = PictureInPicture()
        wrapper.setup(player: AVPlayerLayer())
        let controller = try XCTUnwrap(wrapper.pictureController)
        let spy = DelayedPiPDelegate()
        wrapper.delegate = spy
        var results: [Bool] = []
        wrapper.pictureInPictureController(controller, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler: { results.append($0) })
        wrapper.close()
        spy.completion?(true)
        XCTAssertEqual(results, [false])
        XCTAssertTrue(wrapper.isPictureClose)
    }

    /// 切资源复用 AVPlayer、AVPlayerLayer 与视图；停止清空 item，不让外部视图持有旧资源。
    func testStableLayerAndViewAcrossResources() throws {
        let player = useControlledPlayer()
        let view = engine.view
        let layer = try XCTUnwrap(view.playerLayer as? AVPlayerLayer)
        XCTAssertTrue(layer.player === player)
        prepare()
        prepare(otherAudio)
        XCTAssertTrue(engine.view === view)
        XCTAssertTrue(engine.view.playerLayer === layer)
        XCTAssertTrue(layer.player === player)
        engine.stop()
        XCTAssertNil(layer.player?.currentItem)
    }

    /// 外部持有旧视图也不能阻止引擎销毁；层必须在引擎析构时解除播放器引用。
    func testRetainedViewDoesNotKeepPlayerItemAlive() {
        var temporary: AVVideoPlayer? = AVVideoPlayer(.init())
        temporary?.prepare(resource: audio)
        let view = temporary!.view
        weak var released = temporary
        let layer = view.playerLayer as! AVPlayerLayer
        temporary = nil
        eventually("保留视图时引擎仍应释放") { released == nil }
        XCTAssertNil(layer.player)
    }

    /// 布局及 contentMode 直接映射画面层，设置画面比例不应触发 prepare 或 seek。
    func testLayoutAndVideoGravity() throws {
        let view = engine.view
        let layer = try XCTUnwrap(view.playerLayer as? AVPlayerLayer)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(layer.frame, view.bounds)
        for (mode, gravity) in [(UIView.ContentMode.scaleAspectFit, AVLayerVideoGravity.resizeAspect), (.scaleAspectFill, .resizeAspectFill), (.scaleToFill, .resize)] {
            view.contentMode = mode
            XCTAssertEqual(layer.videoGravity, gravity)
        }
    }

    /// 真正解码当前画面后截图，像素尺寸必须匹配视频，停止后不能返回缓存旧帧。
    func testActualVideoScreenshotAndStop() throws {
        prepare()
        engine.play()
        eventually("视频应实际推进") { self.engine.current > 0.4 }
        let image = try captureFrame()
        XCTAssertEqual(image.size.width, 320)
        XCTAssertEqual(image.size.height, 180)
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 2000)
        engine.stop()
        var count = 0
        engine.screenshot { image in XCTAssertNil(image); count += 1; XCTAssertTrue(Thread.isMainThread) }
        XCTAssertEqual(count, 1)
    }

    /// 无音轨视频仍能播放并截图，不能把音轨存在作为视频解码的前提。
    func testVideoWithoutAudioTrack() throws {
        prepare(try fixture("silent", "mp4"))
        engine.play()
        eventually("无音轨视频也应推进") { self.engine.current > 0.3 }
        XCTAssertEqual(try captureFrame().size.width, 320)
    }

    /// 竖拍旋转元数据应作用到截图，不以横向编码尺寸假冒竖拍输出。
    func testRotatedVideoScreenshot() throws {
        prepare(try fixture("rotated", "mp4"))
        engine.play()
        eventually("竖拍视频实际推进") { self.engine.current > 0.3 }
        let image = try captureFrame()
        XCTAssertEqual(image.size.width, 180)
        XCTAssertEqual(image.size.height, 320)
    }

    /// MOV 容器与 HEVC 编码分别验证实际画面，不根据扩展名推断可用。
    func testMOVAndHEVCDecodeActualFrames() throws {
        for (name, suffix) in [("sample", "mov"), ("hevc", "mp4")] {
            prepare(try fixture(name, suffix))
            engine.play()
            eventually("格式应实际推进") { self.engine.current > 0.3 }
            XCTAssertEqual(try captureFrame().size, CGSize(width: 320, height: 180))
        }
    }

    /// 切到只有音频的资源后不能继续展示旧视频帧；音频兼容播放本身仍保留。
    func testAudioOnlyResourceCannotReturnPreviousVideoFrame() throws {
        prepare()
        engine.play()
        _ = try captureFrame()
        prepare(PlaybackFixtures.compressedAudio)
        engine.play()
        eventually("纯音频仍可推进") { self.engine.current > 0.3 }
        engine.screenshot { XCTAssertNil($0) }
    }

    /// 视频 HLS 必须请求列表与分片，seek 后还要能获取真实解码画面。
    func testHTTPVideoHLSAndSeekProduceFrames() throws {
        let server = try VideoHTTPServer(data: Data())
        server.fixtureDirectory = Bundle.main.url(forResource: "Fixtures", withExtension: nil)!
        defer { server.stop() }
        eventually("HLS 服务就绪") { server.port != nil }
        prepare(server.url("video.m3u8"), seek: 5)
        engine.play()
        eventually("HLS 视频 seek 后继续推进") { self.engine.current > 5.3 }
        XCTAssertGreaterThan(server.requests, 2)
        XCTAssertEqual(try captureFrame().size, CGSize(width: 320, height: 180))
    }

    /// 真实 HTTP 视频缓冲耗尽后恢复解码，暂停时供数恢复不能越过用户意图。
    func testHTTPVideoStallAndPauseRecovery() throws {
        let server = try VideoHTTPServer(data: Data(contentsOf: fixture("long", "mp4")))
        server.chunkSize = 4096
        server.chunkInterval = 0.1
        defer { server.stop() }
        eventually("分块视频服务就绪") { server.port != nil }
        let player = AVPlayer()
        var configuration = VideoPlayerConfiguration()
        configuration.isAutoplay = false
        configuration.preferredBufferDuration = 1
        engine.stop()
        engine = AVVideoPlayer(configuration, player: player)
        prepare(server.url("video.mp4"))
        engine.play()
        eventually("视频应先真实播放") { self.engine.current > 0.2 }
        _ = try captureFrame()
        var stalls = 0
        let token = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: player.currentItem, queue: .main) { _ in stalls += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        server.suspended = true
        eventually("视频应真实耗尽缓冲", timeout: 25) { stalls > 0 }
        server.suspended = false
        let position = engine.current
        eventually("恢复供数后应继续推进", timeout: 15) { self.engine.current > position + 0.3 }
        _ = try captureFrame()
        server.suspended = true
        let count = stalls
        eventually("第二次视频缓冲耗尽", timeout: 25) { stalls > count }
        engine.pause()
        server.suspended = false
        pump(1.5)
        let paused = engine.current
        pump(0.3)
        XCTAssertEqual(engine.current, paused, accuracy: 0.1)
        XCTAssertEqual(player.rate, 0)
    }

    /// PiP 桥接器清理控制器后应及时释放，不延长画面层及页面的持有周期。
    func testPiPWrapperReleases() {
        weak var released: PictureInPicture?
        autoreleasepool {
            let wrapper = PictureInPicture()
            released = wrapper
            wrapper.setup(player: AVPlayerLayer())
            wrapper.close()
        }
        XCTAssertNil(released)
    }

    /// 测试资源缺失直接失败，不退回公网视频，以免把网络环境问题混入回归。
    private func fixture(_ name: String, _ suffix: String) throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: suffix, subdirectory: "Fixtures"))
    }

    /// 持续消费真实视频输出，尚未解码时有界等待；不能以 nil 或假图像充当截图成功。
    private func captureFrame(file: StaticString = #filePath, line: UInt = #line) throws -> UIImage {
        var image: UIImage?
        eventually("应取得真实视频帧", file: file, line: line) { self.engine.screenshot { image = $0 }; return image != nil }
        return try XCTUnwrap(image, file: file, line: line)
    }
}

/// 只记录桥接事件和宿主恢复决定，不模拟系统 PiP 的启动成功。
private final class PiPDelegateRecorder: NSObject, AVPictureInPictureControllerDelegate {
    /// 已转发的开始和停止事件数。
    var starts = 0
    var stops = 0
    /// 模拟宿主是否能够恢复页面。
    var canRestore = false
    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) { starts += 1 }
    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) { stops += 1 }
    func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) { completion(canRestore) }
}

/// 保留宿主异步恢复回调，验证关闭与恢复完成之间的竞争。
private final class DelayedPiPDelegate: NSObject, AVPictureInPictureControllerDelegate {
    /// 仅测试持有系统完成回调，实际宿主必须及时完成。
    var completion: ((Bool) -> Void)?
    func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) { self.completion = completion }
}
