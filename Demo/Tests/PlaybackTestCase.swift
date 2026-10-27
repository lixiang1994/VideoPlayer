import XCTest
import AVFoundation
@testable import VideoPlayer

/// 使用真实媒体和主线程 RunLoop 验证播放器，避免仅断言乐观更新的界面状态。
class PlaybackTestCase: XCTestCase {
    /// 每个测试持有独立实例，禁止串用 shared 污染其他用例。
    var engine: AVVideoPlayer!
    /// 记录事件与线程，并可在回调内模拟业务重入。
    var recorder: PlaybackRecorder!
    /// 固定时长的本地 H.264/AAC 视频，无需网络或人工准备资源。
    var audio: URL { PlaybackFixtures.audio }
    /// 不同 URL 的视频，用于验证旧资源回调隔离。
    var otherAudio: URL { PlaybackFixtures.otherAudio }
    
    override func setUp() {
        super.setUp()
        XCTAssertTrue(Thread.isMainThread)
        var configuration = VideoPlayerConfiguration()
        configuration.isAutoplay = false
        engine = AVVideoPlayer(configuration)
        recorder = PlaybackRecorder()
        engine.add(delegate: recorder)
    }
    
    override func tearDown() {
        recorder.onState = nil
        recorder.onSeekBegan = nil
        recorder.onSeekEnded = nil
        recorder.onControl = nil
        engine.stop()
        engine = nil
        recorder = nil
        pump(0.03)
        super.tearDown()
    }
    
    /// 等待实际就绪；准备前可提交恢复进度，模拟 Demo 的调用顺序。
    func prepare(_ url: URL? = nil, seek: Double? = nil) {
        engine.prepare(resource: url ?? audio)
        if let seek = seek { engine.seek(to: .init(time: seek)) }
        eventually("资源应准备完成") {
            if case .playing = self.engine.state { return true }
            return false
        }
        if let seek = seek {
            eventually("准备阶段的寻时应真正完成") {
                self.recorder.seekEnds.contains(seek)
            }
        }
    }
    
    /// 在主线程继续消费 AVFoundation 异步事件，超时保留具体断言位置。
    func eventually(_ message: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { pump(0.01) }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }
    
    /// 有界运行主循环，用于确认暂停后时间不再前进，而不是阻塞音频回调线程。
    func pump(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }
    
    /// 注入可控 seek completion，真实 AVPlayer 仍负责资源准备和控制状态。
    func useControlledPlayer() -> ControlledPlayer {
        engine.stop()
        var configuration = VideoPlayerConfiguration()
        configuration.isAutoplay = false
        let player = ControlledPlayer()
        engine = AVVideoPlayer(configuration, player: player)
        engine.add(delegate: recorder)
        prepare()
        return player
    }
}

/// 收集对外事件，不读取内核私有字段；回调钩子用于验证同步重入。
final class PlaybackRecorder: VideoPlayerDelegate {
    /// 收到的 seek 开始时间，单位秒。
    var seekBegins: [Double] = []
    /// 收到的有效 seek 结束时间，单位秒。
    var seekEnds: [Double] = []
    /// 是否出现非主线程事件。
    var receivedOffMain = false
    /// 资源状态变化钩子，测试可在这里切资源或停止。
    var onState: ((VideoPlayer.State) -> Void)?
    /// 寻时开始钩子，用于模拟拖动期间 pause/play。
    var onSeekBegan: (() -> Void)?
    
    /// 寻时结束钩子，用于在广播过程中发起下一请求。
    var onSeekEnded: (() -> Void)?
    /// 控制状态钩子，用于验证播放事件内同步暂停。
    var onControl: ((VideoPlayer.ControlState) -> Void)?

    func videoPlayerControlState(_ player: VideoPlayerable, state: VideoPlayer.ControlState) {
        receivedOffMain = receivedOffMain || !Thread.isMainThread
        onControl?(state)
    }

    func videoPlayerState(_ player: VideoPlayerable, state: VideoPlayer.State) {
        receivedOffMain = receivedOffMain || !Thread.isMainThread
        onState?(state)
    }
    
    func videoPlayer(_ player: VideoPlayerable, seekBegan: VideoPlayer.Seek) {
        receivedOffMain = receivedOffMain || !Thread.isMainThread
        seekBegins.append(seekBegan.time)
        onSeekBegan?()
    }
    
    func videoPlayer(_ player: VideoPlayerable, seekEnded: VideoPlayer.Seek) {
        receivedOffMain = receivedOffMain || !Thread.isMainThread
        seekEnds.append(seekEnded.time)
        onSeekEnded?()
    }
}

/// 可确定地延迟、乱序完成 seek，复现系统取消请求仍返回 completion 的行为。
final class ControlledPlayer: AVPlayer {
    /// 每次底层寻时的完成回调，由测试决定完成顺序。
    var completions: [(Bool) -> Void] = []
    /// 已显式移除的周期观察者数量，用于验证实例销毁。
    var removedTimeObservers = 0
    
    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: @escaping (Bool) -> Void) {
        completions.append(completionHandler)
    }
    
    override func removeTimeObserver(_ observer: Any) {
        removedTimeObservers += 1
        super.removeTimeObserver(observer)
    }
}

/// 运行时生成 PCM 文件，测试不依赖 Demo 中的歌曲版权资源或外网服务。
enum PlaybackFixtures {
    /// 24 秒 H.264 / AAC 视频，用于播放、寻时、音轨 mix 与画面验证。
    static let audio = Bundle.main.url(forResource: "sample", withExtension: "mp4", subdirectory: "Fixtures")!
    /// 使用系统 AAC 编码生成的压缩音频，覆盖 PCM 文件以外的解码路径。
    static let compressedAudio = makeAudio(name: "compressed", duration: 24, compressed: true)
    /// 不同 URL 的视频，用于验证切换时旧回调隔离。
    static let otherAudio = Bundle.main.url(forResource: "second", withExtension: "mp4", subdirectory: "Fixtures")!
    /// 0.6 秒视频，用于真实结束与循环。
    static let shortAudio = Bundle.main.url(forResource: "short", withExtension: "mp4", subdirectory: "Fixtures")!
    
    /// 生成低振幅正弦波；失败时直接暴露测试环境错误。
    private static func makeAudio(name: String, duration: Double, compressed: Bool = false) -> URL {
        let ext = compressed ? "m4a" : "wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("videoplayer-tests-\(name).\(ext)")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let frames = AVAudioFrameCount(duration * 44100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 440 * 2 * .pi / 44100) * 0.01)
            }
        }
        do {
            let settings: [String: Any] = compressed ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 64000] : format.settings
            let file = try AVAudioFile(forWriting: url, settings: settings)
            try file.write(from: buffer)
        } catch {
            fatalError("测试音频生成失败: \(error)")
        }
        return url
    }
}
