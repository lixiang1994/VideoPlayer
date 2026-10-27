import XCTest
import AVFoundation
@testable import VideoPlayer

/// 确定性验证乱序 completion、业务回调重入以及观察者释放。
final class SeekLifecycleTests: PlaybackTestCase {
    /// 第一个代理在旧 seekBegan 内再次寻时，后续代理只能收到仍有效的新请求。
    func testReentrantSeekDoesNotDeliverStaleBeganToOtherDelegates() {
        let player = useControlledPlayer()
        let second = PlaybackRecorder()
        engine.add(delegate: second)
        recorder.onSeekBegan = {
            self.recorder.onSeekBegan = nil
            self.engine.seek(to: .init(time: 7))
        }
        engine.seek(to: .init(time: 3))
        XCTAssertEqual(player.completions.count, 1)
        XCTAssertEqual(second.seekBegins, [7])
        XCTAssertEqual(engine.current, 7)
    }

    /// seekEnded 内发起新寻时后，其余代理不能在新 began 后收到旧 ended。
    func testReentrantSeekDoesNotDeliverStaleEndedToOtherDelegates() {
        let player = useControlledPlayer()
        let second = PlaybackRecorder()
        engine.add(delegate: second)
        recorder.onSeekEnded = { self.engine.seek(to: .init(time: 7)) }
        engine.seek(to: .init(time: 3))
        player.completions[0](true)
        pump(0.03)
        XCTAssertEqual(second.seekBegins, [3, 7])
        XCTAssertTrue(second.seekEnds.isEmpty)
        XCTAssertEqual(engine.current, 7)
    }

    /// 第一个代理收到 playing 后暂停，其余代理不得收到晚于 pausing 的旧 playing。
    func testReentrantPauseDoesNotDeliverStaleControl() {
        prepare()
        let second = PlaybackRecorder()
        var controls: [VideoPlayer.ControlState] = []
        second.onControl = { controls.append($0) }
        engine.add(delegate: second)
        recorder.onControl = { state in
            if state == .playing { self.engine.pause() }
        }
        engine.play()
        pump(0.1)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertEqual(controls, [.pausing])
    }

    /// ready 的第一个代理同步处理 EOF，其余代理只能收到最新的 finished。
    func testReentrantFinishDoesNotDeliverStaleReady() {
        engine.stop()
        let player = ControlledPlayer()
        var configuration = VideoPlayerConfiguration()
        configuration.isAutoplay = false
        engine = AVVideoPlayer(configuration, player: player)
        engine.add(delegate: recorder)
        let second = PlaybackRecorder()
        var states: [String] = []
        second.onState = { state in
            if case .playing = state { states.append("playing") }
            if case .finished = state { states.append("finished") }
        }
        engine.add(delegate: second)
        recorder.onState = { state in
            if case .playing = state {
                NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem!)
            }
        }
        engine.prepare(resource: audio)
        eventually("ready 内的结束应生效") { if case .finished = self.engine.state { return true }; return false }
        XCTAssertEqual(states, ["finished"])
    }

    /// 被取消的旧 seek 在新 seek 之后回调，也不能清掉新请求或重复完成。
    func testLateCancelledSeekCannotOverwriteNewSeek() {
        let player = useControlledPlayer()
        var first: [Bool] = []
        var second: [Bool] = []
        engine.seek(to: .init(time: 5, completion: { first.append($0) }))
        engine.seek(to: .init(time: 11, completion: { second.append($0) }))
        XCTAssertEqual(first, [false])
        player.completions[0](false)
        pump(0.03)
        XCTAssertEqual(engine.current, 11)
        XCTAssertTrue(second.isEmpty)
        player.completions[1](true)
        pump(0.03)
        XCTAssertEqual(first, [false])
        XCTAssertEqual(second, [true])
        XCTAssertEqual(recorder.seekEnds, [11])
    }
    
    /// seek 成功回调迟到新资源之后，不能上报旧进度或恢复旧播放意图。
    func testOldSeekCompletionAfterResourceSwitchIsIgnored() {
        let player = useControlledPlayer()
        var results: [Bool] = []
        engine.seek(to: .init(time: 18, completion: { results.append($0) }))
        prepare(otherAudio)
        player.completions[0](true)
        pump(0.05)
        XCTAssertEqual(results, [false])
        XCTAssertEqual(engine.resource?.value, otherAudio)
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
        XCTAssertTrue(recorder.seekEnds.isEmpty)
    }
    
    /// 停止使已发出的 seek 失效，迟到回调不能把 stopped 改回 playing。
    func testStopCancelsSeekExactlyOnce() {
        let player = useControlledPlayer()
        var results: [Bool] = []
        engine.seek(to: .init(time: 10, completion: { results.append($0) }))
        engine.stop()
        player.completions[0](true)
        pump(0.03)
        XCTAssertEqual(results, [false])
        if case .stopped = engine.state {} else { XCTFail("停止后状态不应被旧回调修改") }
        XCTAssertEqual(engine.current, 0)
        XCTAssertNil(engine.resource)
    }
    
    /// completion 内的新 seek 必须完整保留，旧请求不能随后清空它。
    func testCompletionCanStartAnotherSeek() {
        let player = useControlledPlayer()
        engine.seek(to: .init(time: 3, completion: { _ in
            self.engine.seek(to: .init(time: 7))
        }))
        player.completions[0](true)
        pump(0.03)
        XCTAssertEqual(player.completions.count, 2)
        XCTAssertEqual(engine.current, 7)
        player.completions[1](true)
        pump(0.03)
        XCTAssertEqual(recorder.seekEnds, [7])
    }
    
    /// 取消旧 seek 的 completion 也能切资源，外层 seek 不得继续作用于旧 item。
    func testCancelledCompletionCanPrepareNewResource() {
        let player = useControlledPlayer()
        engine.seek(to: .init(time: 3, completion: { _ in self.engine.prepare(resource: self.otherAudio) }))
        engine.seek(to: .init(time: 7))
        eventually("重入准备应完成") { self.engine.resource?.value == self.otherAudio }
        pump(0.05)
        XCTAssertEqual(player.completions.count, 1)
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
    }
    
    /// ready 状态广播中同步 stop，旧的 ready 处理不能继续开播。
    func testDelegateCanStopWhenReady() {
        recorder.onState = { state in
            if case .playing = state { self.engine.stop() }
        }
        engine.prepare(resource: audio)
        eventually("代理停止应清空资源") { self.engine.resource == nil }
        pump(0.05)
        if case .stopped = engine.state {} else { XCTFail("ready 回调后必须保持停止") }
    }
    
    /// 准备完成前被覆盖的 seek 也必须给出取消结果。
    func testPendingSeekCompletesWhenSuperseded() {
        var results: [Bool] = []
        engine.prepare(resource: audio)
        engine.seek(to: .init(time: 2, completion: { results.append($0) }))
        engine.seek(to: .init(time: 4))
        XCTAssertEqual(results, [false])
        eventually("最后一个待处理 seek 应完成") { self.recorder.seekEnds.contains(4) }
    }
    
    /// 当前请求失败时必须返回底层实际进度，不能把目标位置作为成功校准值。
    func testFailedSeekDoesNotKeepOptimisticProgress() {
        let player = useControlledPlayer()
        var results: [Bool] = []
        engine.seek(to: .init(time: 20, completion: { results.append($0) }))
        player.completions[0](false)
        pump(0.03)
        XCTAssertEqual(results, [false])
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
    }
    
    /// seekBegan 内停止时，不得继续向底层提交已失效的寻时请求。
    func testStopFromSeekBeganDoesNotSubmitRequest() {
        let player = useControlledPlayer()
        var results: [Bool] = []
        recorder.onSeekBegan = { self.engine.stop() }
        engine.seek(to: .init(time: 10, completion: { results.append($0) }))
        XCTAssertTrue(player.completions.isEmpty)
        XCTAssertEqual(results, [false])
        XCTAssertNil(engine.resource)
    }
    
    /// 业务成功回调内切资源后，旧 seekEnded 事件不能继续上报到新资源。
    func testCompletionCanSwitchResource() {
        let player = useControlledPlayer()
        engine.seek(to: .init(time: 10, completion: { _ in
            self.engine.prepare(resource: self.otherAudio)
        }))
        player.completions[0](true)
        pump(0.05)
        XCTAssertEqual(engine.resource?.value, otherAudio)
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
        XCTAssertTrue(recorder.seekEnds.isEmpty)
    }
    
    /// 旧 item 的结束、失败通知不能影响切换后的新单集。
    func testNotificationsFromOldItemAreIgnored() {
        let player = useControlledPlayer()
        let oldItem = player.currentItem!
        prepare(otherAudio)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: oldItem)
        pump(0.03)
        if case .playing = engine.state {} else { XCTFail("旧通知不得结束或清空新单集") }
        XCTAssertEqual(engine.resource?.value, otherAudio)
    }
    
    /// 销毁实例无需调用者先 stop，底层 item 和周期观察者都应解除。
    func testReleaseTearsDownPlayer() {
        engine.stop()
        let player = ControlledPlayer()
        var temporary: AVVideoPlayer? = AVVideoPlayer(.init(), player: player)
        weak var weakEngine = temporary
        temporary?.prepare(resource: audio)
        temporary = nil
        pump(0.05)
        XCTAssertNil(weakEngine)
        XCTAssertNil(player.currentItem)
        XCTAssertEqual(player.removedTimeObservers, 1)
    }
}
