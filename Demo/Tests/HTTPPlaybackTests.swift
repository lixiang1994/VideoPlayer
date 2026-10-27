import XCTest
import Network
import AVFoundation
@testable import VideoPlayer

/// 通过本机 HTTP 服务验证真实网络加载、重定向、Range 与失败恢复，不依赖公网资源。
final class HTTPPlaybackTests: PlaybackTestCase {
    /// HTTP 视频文件动态 mix 必须使用同一 asset，保持实际画面 item、进度与暂停意图。
    func testHTTPVideoMixKeepsPlaybackAndPause() throws {
        let asset = AVURLAsset(url: server.url("video.mp4"))
        engine.prepare(resource: asset)
        eventually("网络资源应就绪") { if case .playing = self.engine.state { return true }; return false }
        let track = try XCTUnwrap(asset.tracks(withMediaType: .audio).first)
        let parameter = AVMutableAudioMixInputParameters(track: track)
        parameter.setVolume(0.25, at: .zero)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameter]
        let layer = try XCTUnwrap(engine.view.playerLayer as? AVPlayerLayer)
        let item = try XCTUnwrap(layer.player?.currentItem)
        engine.play()
        eventually("网络视频应推进") { self.engine.current > 0.4 }
        let position = engine.current
        XCTAssertTrue(engine.update(audioMix: mix, for: asset))
        XCTAssertTrue(layer.player?.currentItem === item)
        eventually("更新后继续原进度") { self.engine.current > position + 0.2 }
        engine.pause()
        XCTAssertTrue(engine.update(audioMix: nil, for: asset))
        pump(0.2)
        XCTAssertEqual(layer.player?.rate, 0)
    }

    /// 每个测试使用独立端口，串行结束后主动停止监听。
    private var server: VideoHTTPServer!
    
    override func setUp() {
        super.setUp()
        server = try! VideoHTTPServer(data: Data(contentsOf: audio))
        eventually("本机 HTTP 服务应就绪") { self.server.port != nil }
    }
    
    override func tearDown() {
        engine.stop()
        server.stop()
        server = nil
        super.tearDown()
    }
    
    /// 真实延迟响应仍应解码并播放，不能只验证立即完成的本机下载。
    func testDelayedResponseEventuallyPlays() {
        server.responseDelay = 1
        prepare(server.url("video.mp4"))
        XCTAssertGreaterThan(server.requests, 0)
        engine.play()
        eventually("延迟响应后应实际推进") { self.engine.current > 0.2 }
    }

    /// 等待网络响应时切资源，迟到响应不能覆盖本地资源。
    func testSwitchResourceWhileResponseDelayed() {
        server.responseDelay = 1
        engine.prepare(resource: server.url("video.mp4"))
        eventually("应先发出网络请求") { self.server.requests > 0 }
        prepare(otherAudio)
        pump(1.2)
        XCTAssertEqual(engine.resource?.value, otherAudio)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
    }

    /// 响应尚未返回时暂停，后续网络就绪不能重新设置自动播放意图。
    func testPauseDuringDelayedResponse() {
        server.responseDelay = 0.7
        engine.stop()
        engine = AVVideoPlayer(.init())
        engine.prepare(resource: server.url("video.mp4"))
        eventually("应先进入真实网络等待") { self.server.requests > 0 }
        engine.pause()
        eventually("慢响应最终应就绪") { if case .playing = self.engine.state { return true }; return false }
        pump(0.2)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
    }

    /// 服务在响应前关闭连接；用户 stop 后重试正常服务不应残留旧请求或状态。
    func testConnectionDropThenExplicitRetry() {
        server.dropsConnection = true
        engine.prepare(resource: server.url("video.mp4"))
        eventually("应收到至少一次将被断开的请求") { self.server.requests > 0 }
        pump(0.2)
        engine.stop()
        server.dropsConnection = false
        prepare(server.url("video.mp4"))
        engine.play()
        eventually("重新准备后应恢复播放") { self.engine.current > 0.2 }
    }

    /// 鉴权失败必须进入失败状态，不能把错误正文当成可播放数据。
    func testHTTPAuthorizationFailureCanRecover() {
        engine.prepare(resource: server.url("unauthorized"))
        eventually("401 应报告失败") { if case .failed = self.engine.state { return true }; return false }
        prepare(server.url("video.mp4"))
        engine.play()
        eventually("换有效地址应恢复") { self.engine.current > 0.2 }
    }

    /// 有响应但没有合法音频头时必须失败，并允许后续正常播放。
    func testCorruptMediaFailsAndRecovers() {
        server.stop()
        server = try! VideoHTTPServer(data: Data(repeating: 0xFF, count: 8192))
        eventually("坏文件服务应就绪") { self.server.port != nil }
        engine.prepare(resource: server.url("video.mp4"))
        eventually("损坏音频应失败") { if case .failed = self.engine.state { return true }; return false }
        prepare()
        engine.play()
        eventually("坏文件之后应恢复") { self.engine.current > 0.2 }
    }

    /// HLS VOD 需要请求播放列表和多个分片，实际寻时后继续解码推进。
    func testHLSVODSeekAndPlay() {
        server.fixtureDirectory = Bundle.main.url(forResource: "Fixtures", withExtension: nil)!
        prepare(server.url("tone.m3u8"), seek: 5)
        engine.play()
        eventually("HLS 寻时后应实际推进") { self.engine.current > 5.3 }
        XCTAssertGreaterThan(server.requests, 2)
    }

    /// 使用长 MP3 分块供数，真实的系统卡顿通知才证明已耗尽缓冲。
    func testStreamStallAndRecovery() {
        let player = prepareStreamingMP3()
        var stalled = false
        let token = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: player.currentItem, queue: .main) { _ in stalled = true }
        defer { NotificationCenter.default.removeObserver(token) }
        server.suspended = true
        let bytes = server.sentBytes
        eventually("停止供数应触发系统卡顿通知，已发送 \(bytes) 字节", timeout: 20) { stalled }
        XCTAssertEqual(server.sentBytes, bytes)
        server.suspended = false
        let time = engine.current
        eventually("恢复供数后应继续推进", timeout: 15) { self.engine.current > time + 0.3 && player.rate > 0 && self.engine.control == .playing && self.server.sentBytes > bytes }
    }

    /// 系统确认卡顿后主动暂停，恢复供数不得重新启动底层播放速率。
    func testPauseWhileStreamStalledPreventsResume() {
        let player = prepareStreamingMP3()
        var stalled = false
        let token = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: player.currentItem, queue: .main) { _ in stalled = true }
        defer { NotificationCenter.default.removeObserver(token) }
        server.suspended = true
        eventually("应先触发真实卡顿通知", timeout: 20) { stalled }
        engine.pause()
        server.suspended = false
        pump(2)
        XCTAssertEqual(player.rate, 0)
        XCTAssertEqual(engine.control, .pausing)
        let time = engine.current
        pump(0.5)
        XCTAssertEqual(engine.current, time, accuracy: 0.15)
    }

    /// 长音频避免在 ready 前已经下载完整文件；只接管服务器供数，不替换系统解码。
    private func prepareStreamingMP3() -> AVPlayer {
        server.stop()
        let url = Bundle.main.url(forResource: "tone", withExtension: "mp3", subdirectory: "Fixtures")!
        server = try! VideoHTTPServer(data: Data(contentsOf: url))
        server.chunkInterval = 0.1
        server.chunkSize = 4096
        eventually("分块服务应就绪") { self.server.port != nil }
        let player = AVPlayer()
        var configuration = VideoPlayerConfiguration()
        configuration.isAutoplay = false
        configuration.preferredBufferDuration = 1
        engine.stop()
        engine = AVVideoPlayer(configuration, player: player)
        prepare(server.url("audio.mp3"))
        engine.play()
        eventually("先实际播放") { self.engine.current > 0.2 }
        return player
    }

    /// HTTP 音频需要真正下载并解码；暂停配置不能被网络就绪覆盖。
    func testHTTPPrepareSeekAndPlay() {
        prepare(server.url("video.mp4"), seek: 8)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertEqual(engine.current, 8, accuracy: 0.1)
        engine.play()
        eventually("网络寻时后应从目标位置继续播放") { self.engine.current > 8.15 }
        XCTAssertGreaterThan(server.requests, 0)
    }
    
    /// URL 重定向不能改变外部持有的资源标识或导致准备失败。
    func testHTTPRedirect() {
        let url = server.url("redirect")
        prepare(url)
        engine.play()
        eventually("重定向资源应播放") { self.engine.current > 0.1 }
        XCTAssertEqual(engine.resource?.value, url)
    }
    
    /// 压缩的 AAC/M4A 同样需要走远程加载和解码，不能只验证 WAV。
    func testHTTPCompressedAudio() {
        server.stop()
        server = try! VideoHTTPServer(data: Data(contentsOf: PlaybackFixtures.compressedAudio))
        eventually("压缩音频服务应就绪") { self.server.port != nil }
        prepare(server.url("audio.m4a"), seek: 8)
        engine.play()
        eventually("压缩网络音频应从寻时位置继续播放") { self.engine.current > 8.15 }
    }
    
    /// 网络准备期间的 pause 必须覆盖默认自动播放意图。
    func testPauseWhileHTTPPreparing() {
        engine.stop()
        engine = AVVideoPlayer(.init())
        engine.prepare(resource: server.url("video.mp4"))
        engine.pause()
        eventually("网络资源应就绪") { if case .playing = self.engine.state { return true }; return false }
        pump(0.2)
        XCTAssertEqual(engine.control, .pausing)
        XCTAssertEqual(engine.current, 0, accuracy: 0.05)
    }
    
    /// 网络准备中停止后，迟到的加载回调不能重新进入 ready 或恢复资源。
    func testStopWhileHTTPPreparing() {
        engine.prepare(resource: server.url("video.mp4"))
        engine.stop()
        pump(0.2)
        if case .stopped = engine.state {} else { XCTFail("停止后不得被网络回调恢复") }
        XCTAssertNil(engine.resource)
    }
    
    /// 网络错误显式失败，随后切到本地文件仍可正常恢复。
    func testHTTPFailureThenLocalPlayback() {
        engine.prepare(resource: server.url("missing"))
        eventually("404 应失败") { if case .failed = self.engine.state { return true }; return false }
        prepare()
        engine.play()
        eventually("网络失败后应可恢复") { self.engine.current > 0.1 }
    }
}

/// 最小测试 HTTP 服务器，支持 HEAD、字节范围和重定向，仅监听本机临时端口。
final class VideoHTTPServer {
    /// 媒体数据固定在内存中，避免网络处理线程触碰测试播放器状态。
    private let data: Data
    /// 专用网络队列，连接接收和发送均串行处理。
    private let queue = DispatchQueue(label: "audio.player.tests.http")
    /// 监听器在测试结束时显式取消。
    private let listener: NWListener
    /// 活跃连接保留到测试结束，确保失败用例也能回收连接。
    private var connections: [NWConnection] = []
    /// 主线程发布的就绪端口，nil 表示尚未监听。
    private(set) var port: UInt16?
    /// 主线程记录实际请求数量，防止测试只验证本地乐观状态。
    private(set) var requests = 0
    
    /// 可控响应延迟，单位秒，跨线程访问均在网络队列串行处理。
    var responseDelay: TimeInterval {
        get { return queue.sync { delay } }
        set { queue.sync { delay = newValue } }
    }
    /// 网络队列持有的延迟值。
    private var delay: TimeInterval = 0
    /// 可选的 HLS 夹具目录，只允许按单个文件名访问测试资源。
    var fixtureDirectory: URL? {
        get { return queue.sync { directory } }
        set { queue.sync { directory = newValue } }
    }
    /// 网络队列持有的资源根目录。
    private var directory: URL?
    /// 测试通过同步入口设置断流开关，避免主线程与网络队列并发读写。
    var dropsConnection: Bool {
        get { return queue.sync { shouldDropConnection } }
        set { queue.sync { shouldDropConnection = newValue } }
    }
    /// 仅由网络队列读写的断流状态。
    private var shouldDropConnection = false

    /// 每个 32 KB 数据块之间的间隔，零表示一次性发送；仅由专用队列读写。
    var chunkInterval: TimeInterval {
        get { return queue.sync { interval } }
        set { queue.sync { interval = newValue } }
    }
    /// 可暂停所有活跃响应的供数，模拟真实下载中断与恢复。
    var suspended: Bool {
        get { return queue.sync { isSuspended } }
        set { queue.sync { isSuspended = newValue } }
    }
    /// 网络队列持有的分块间隔和供数状态，避免测试线程数据竞争。
    private var interval: TimeInterval = 0
    private var isSuspended = false
    /// 累计发出的 HTTP 字节数，用于确认缓冲耗尽前并未完整下载媒体。
    var sentBytes: Int { return queue.sync { bytes } }
    /// 只由网络队列累加。
    private var bytes = 0
    /// 每个发送块的字节数，至少为一，缩小后可控制启动缓冲量。
    var chunkSize: Int {
        get { return queue.sync { blockSize } }
        set { queue.sync { blockSize = Swift.max(1, newValue) } }
    }
    /// 网络队列持有的块大小，默认 32 KB。
    private var blockSize = 32768
    /// stop 后不得继续发送排队的延迟响应。
    private var isStopped = false

    /// 创建临时端口监听，端口状态回到主线程供 XCTest 等待。
    init(data: Data) throws {
        self.data = data
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }
            DispatchQueue.main.async { [weak self] in self?.port = self?.listener.port?.rawValue }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(connection, pending: Data())
        }
        listener.start(queue: queue)
    }
    
    /// 服务仅供当前测试使用，不要求固定端口或外网权限。
    func url(_ path: String) -> URL {
        return URL(string: "http://127.0.0.1:\(port!)/\(path)")!
    }
    
    /// 在网络队列取消所有连接，避免 XCTest 退出后遗留监听。
    func stop() {
        listener.cancel()
        queue.sync {
            isStopped = true
            connections.forEach { $0.cancel() }
            connections = []
        }
    }
    
    /// 收齐请求头后再处理，兼容 TCP 分片，不依赖一次 receive 收到完整报文。
    private func receive(_ connection: NWConnection, pending: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] bytes, _, complete, error in
            guard let self = self else { return }
            var pending = pending
            if let bytes = bytes { pending.append(bytes) }
            if let request = String(data: pending, encoding: .utf8), request.contains("\r\n\r\n") {
                DispatchQueue.main.async { [weak self] in self?.requests += 1 }
                if self.shouldDropConnection {
                    connection.cancel()
                    return
                }
                self.queue.asyncAfter(deadline: .now() + self.delay) { [weak self] in
                    self?.respond(connection, request: request)
                }
            } else if !complete, error == nil {
                self.receive(connection, pending: pending)
            } else {
                connection.cancel()
            }
        }
    }
    
    /// 模拟标准文件服务，Range 的结束偏移为闭区间。
    private func respond(_ connection: NWConnection, request: String) {
        guard !isStopped else { return }
        let lines = request.components(separatedBy: "\r\n")
        let first = lines[0].components(separatedBy: " ")
        let path = first.count > 1 ? first[1] : ""
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let fixture = directory.flatMap { try? Data(contentsOf: $0.appendingPathComponent(filename)) }
        let data = fixture ?? self.data
        var status = "200 OK"
        var type = path.hasSuffix(".mp3") ? "audio/mpeg" : path.hasSuffix(".m3u8") ? "application/vnd.apple.mpegurl" : path.hasSuffix(".ts") ? "video/mp2t" : path.hasSuffix(".m4a") ? "audio/mp4" : "audio/wav"
        if path.hasSuffix(".mp4") { type = "video/mp4" }
        var headers = "Content-Type: \(type)\r\nAccept-Ranges: bytes\r\n"
        var body = data
        if path == "/redirect" {
            status = "302 Found"
            headers = "Location: /video.mp4\r\n"
            body = Data()
        } else if path == "/unauthorized" {
            status = "401 Unauthorized"
            body = Data()
        } else if path != "/video.mp4", path != "/audio.m4a", path != "/audio.mp3", fixture == nil {
            status = "404 Not Found"
            body = Data()
        } else if let range = lines.first(where: { $0.lowercased().hasPrefix("range: bytes=") }) {
            let values = range.components(separatedBy: "=")[1].components(separatedBy: "-")
            let start = Int(values[0]) ?? 0
            let end = Swift.min(Int(values.last ?? "") ?? (data.count - 1), data.count - 1)
            if start >= 0, start <= end {
                status = "206 Partial Content"
                body = data.subdata(in: start..<(end + 1))
                headers += "Content-Range: bytes \(start)-\(end)/\(data.count)\r\n"
            } else {
                status = "416 Range Not Satisfiable"
                body = Data()
            }
        }
        let head = "HTTP/1.1 \(status)\r\n\(headers)Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(head.utf8)
        if first.first != "HEAD" { response.append(body) }
        if interval > 0 {
            send(response, offset: 0, connection: connection)
        } else {
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// 分块发送保留标准 Content-Length；暂停期间保留 TCP 连接，恢复后从原偏移继续。
    private func send(_ data: Data, offset: Int, connection: NWConnection) {
        guard !isStopped else { return }
        if isSuspended {
            queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.send(data, offset: offset, connection: connection)
            }
            return
        }
        let end = Swift.min(offset + blockSize, data.count)
        bytes += end - offset
        connection.send(content: data.subdata(in: offset..<end), completion: .contentProcessed { [weak self] error in
            guard let self = self, !self.isStopped else { return }
            guard error == nil, end < data.count else { connection.cancel(); return }
            self.queue.asyncAfter(deadline: .now() + self.interval) { [weak self] in
                self?.send(data, offset: end, connection: connection)
            }
        })
    }

}
