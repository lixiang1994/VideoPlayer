import XCTest
import AVKit
@testable import VideoPlayer
@testable import Demo

/// 通过页面实际控件验证资源身份、异步准备和界面选项，不只验证播放器底层接口。
final class DemoIntegrationTests: PlaybackTestCase {
    /// 诊断页必须保留列表和返回按钮；真实退出时清理资源，不能只显示一个无法返回的导航根页面。
    func testDiagnosticsPreservesNavigationAndStopsOnReturn() throws {
        for existingNavigation in [false, true] {
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let original = existingNavigation
                ? UIStoryboard(name: "Main", bundle: .main).instantiateInitialViewController() as? UINavigationController
                : nil
            window.rootViewController = original
            let diagnostics = VideoDeviceDiagnostics(window: window, requestsPictureInPicture: false)
            defer { window.isHidden = true; window.rootViewController = nil }
            let navigation = try XCTUnwrap(window.rootViewController as? UINavigationController)
            if let original = original { XCTAssertTrue(navigation === original) }
            XCTAssertTrue(navigation.viewControllers.first is ViewController)
            let page = try XCTUnwrap(navigation.topViewController as? SimplePlayerViewController)
            let player = try XCTUnwrap(page.player)
            defer { player.stop() }
            eventually("诊断视频应实际播放", timeout: 15) { player.current > 0.3 }
            let trace = XCTAttachment(string: "existingNavigation=\(existingNavigation), state=\(player.state), control=\(player.control), loading=\(player.loading), current=\(player.current), app=\(UIApplication.shared.applicationState.rawValue), PiP=\(page.isPictureInPictureActive)")
            trace.lifetime = .keepAlways
            add(trace)
            pump(1)
            XCTAssertTrue(window.rootViewController === navigation)
            XCTAssertFalse(navigation.isNavigationBarHidden)
            XCTAssertEqual(navigation.viewControllers.count, 2)
            XCTAssertNotNil(navigation.navigationBar.backItem)
            XCTAssertFalse(page.navigationItem.hidesBackButton)
            navigation.popViewController(animated: false)
            pump(0.2)
            XCTAssertTrue(navigation.topViewController is ViewController)
            XCTAssertNil(player.resource)
            XCTAssertFalse(page.isPictureInPictureActive)
            withExtendedLifetime(diagnostics) {}
        }
    }

    /// 本地与 HTTP 文件都用媒体时钟验证倍速，暂停期间的目标和实际 AVPlayer 状态分别检查。
    func testPageRateTargetAndMediaClockForLocalAndHTTP() throws {
        let server = try VideoHTTPServer(data: Data(contentsOf: audio))
        defer { server.stop() }
        eventually("本机 HTTP 服务应就绪") { server.port != nil }
        for url in [audio, server.url("video.mp4")] {
            let page = SimplePlayerViewController.instance(2)
            page.loadViewIfNeeded()
            page.preparePlayback(url: url)
            let player = try XCTUnwrap(page.player)
            defer { player.stop() }
            eventually("视频应实际播放") { player.current > 0.3 }
            let layer = try XCTUnwrap(player.view.playerLayer as? AVPlayerLayer)
            let avPlayer = try XCTUnwrap(layer.player)
            let item = try XCTUnwrap(avPlayer.currentItem)
            let rates: UISegmentedControl = try control("video.rate", in: page.view)
            let label: UILabel = try control("video.diagnostics", in: page.view)
            player.pause()
            rates.selectedSegmentIndex = 2
            rates.sendActions(for: .valueChanged)
            XCTAssertTrue(label.text?.contains("目标 1.5×") == true)
            XCTAssertTrue(label.text?.contains("已暂停") == true)
            XCTAssertEqual(avPlayer.rate, 0)
            let position = avPlayer.currentTime().seconds
            pump(0.2)
            XCTAssertEqual(avPlayer.currentTime().seconds, position, accuracy: 0.02)
            player.play()
            for (index, target) in [(2, 1.5), (3, 2.0)] {
                rates.selectedSegmentIndex = index
                rates.sendActions(for: .valueChanged)
                eventually("底层应执行所选倍率") { avPlayer.timeControlStatus == .playing && abs(Double(avPlayer.rate) - target) < 0.01 }
                // 避开起播边界；采样期间不 seek、不切资源、不允许缓冲或暂停。
                pump(0.1)
                let mediaStart = avPlayer.currentTime().seconds
                let clockStart = ProcessInfo.processInfo.systemUptime
                pump(0.4)
                let measured = (avPlayer.currentTime().seconds - mediaStart) / (ProcessInfo.processInfo.systemUptime - clockStart)
                XCTAssertEqual(avPlayer.timeControlStatus, .playing)
                XCTAssertEqual(player.loading, .ended)
                XCTAssertTrue(avPlayer.currentItem === item)
                XCTAssertEqual(measured, target, accuracy: 0.25)
                let measurement = XCTAttachment(string: "\(url.isFileURL ? "local" : "HTTP") MP4: target=\(target), AVPlayer.rate=\(avPlayer.rate), media/uptime=\(measured)")
                measurement.lifetime = .keepAlways
                add(measurement)
            }
            player.stop()
            XCTAssertTrue(label.text?.contains("已停止") == true)
        }
        XCTAssertGreaterThan(server.requests, 0)
    }

    /// 默认网络案例是已知 HLS；未播放时就应明确禁用 mix，进度刷新不能覆盖兼容提示。
    func testNetworkHLSExplainsUnsupportedMix() throws {
        let page = SimplePlayerViewController.instance(0)
        page.loadViewIfNeeded()
        let mix: UISegmentedControl = try control("video.mix", in: page.view)
        let status: UILabel = try control("video.mixStatus", in: page.view)
        let sources: UISegmentedControl = try control("video.networkSource", in: page.view)
        XCTAssertEqual(sources.numberOfSegments, 2)
        XCTAssertEqual(sources.selectedSegmentIndex, 0)
        XCTAssertFalse(mix.isEnabled)
        XCTAssertTrue(status.text?.contains("HLS") == true)
        mix.selectedSegmentIndex = 1
        mix.sendActions(for: .valueChanged)
        XCTAssertEqual(mix.selectedSegmentIndex, 0)
        XCTAssertNil((page.player as? AVVideoAudioMixControlling)?.audioMix)
        page.videoPlayer(page.player!, updatedCurrent: 1)
        XCTAssertTrue(status.text?.contains("HLS") == true)
    }

    /// 网络文件可提交 mix 并继续原进度；切回真实 HLS 后必须清除配置并禁用无效开关。
    func testNetworkPageMP4MixAndHLSCompatibility() throws {
        let server = try VideoHTTPServer(data: Data(contentsOf: audio))
        server.fixtureDirectory = Bundle.main.url(forResource: "Fixtures", withExtension: nil)!
        defer { server.stop() }
        eventually("本机网络案例服务应就绪") { server.port != nil }
        let page = SimplePlayerViewController.instance(0)
        page.loadViewIfNeeded()
        page.preparePlayback(url: server.url("video.mp4"))
        let player = try XCTUnwrap(page.player)
        defer { player.stop() }
        eventually("网络 MP4 应实际起播") { player.current > 0.3 }
        let mix: UISegmentedControl = try control("video.mix", in: page.view)
        let status: UILabel = try control("video.mixStatus", in: page.view)
        let layer = try XCTUnwrap(player.view.playerLayer as? AVPlayerLayer)
        let item = try XCTUnwrap(layer.player?.currentItem)
        XCTAssertTrue(mix.isEnabled)
        let position = player.current
        mix.selectedSegmentIndex = 1
        mix.sendActions(for: .valueChanged)
        eventually("文件型资源应提交 25% 配置") { item.audioMix != nil }
        XCTAssertTrue(layer.player?.currentItem === item)
        eventually("提交后应保持原进度推进") { player.current > position + 0.2 }
        XCTAssertTrue(status.text?.contains("25%") == true)
        page.preparePlayback(url: server.url("video.m3u8"))
        XCTAssertFalse(mix.isEnabled)
        eventually("HLS 视频仍应正常播放") { player.resource?.value.pathExtension == "m3u8" && player.current > 0.3 }
        XCTAssertNil((player as? AVVideoAudioMixControlling)?.audioMix)
        XCTAssertFalse(mix.isEnabled)
        XCTAssertTrue(status.text?.contains("HLS") == true)
    }

    /// 播放中切换 mix 必须保持 item 与进度；暂停时恢复原始音轨不能自动播放。
    func testPageMixKeepsItemPositionAndPause() throws {
        let page = SimplePlayerViewController.instance(2)
        page.loadViewIfNeeded()
        page.preparePlayback()
        let player = try XCTUnwrap(page.player)
        defer { player.stop() }
        eventually("页面应起播") { player.current > 0.4 }
        let layer = try XCTUnwrap(player.view.playerLayer as? AVPlayerLayer)
        let item = try XCTUnwrap(layer.player?.currentItem)
        let mix: UISegmentedControl = try control("video.mix", in: page.view)
        let position = player.current
        mix.selectedSegmentIndex = 1
        mix.sendActions(for: .valueChanged)
        eventually("页面应真正安装 mix") { item.audioMix != nil }
        XCTAssertTrue(layer.player?.currentItem === item)
        XCTAssertGreaterThanOrEqual(player.current, position)
        player.pause()
        mix.selectedSegmentIndex = 0
        mix.sendActions(for: .valueChanged)
        XCTAssertNil(item.audioMix)
        pump(0.2)
        XCTAssertEqual(layer.player?.rate, 0)
    }

    /// 同页覆盖真实格式切换，异步 mix 不能落到新资源；画面模式和倍速不换 item。
    func testPageSourcesControlsAndScreenshot() throws {
        let page = SimplePlayerViewController.instance(2)
        page.loadViewIfNeeded()
        let player = try XCTUnwrap(page.player)
        defer { player.stop() }
        let sources: UISegmentedControl = try control("video.source", in: page.view)
        for index in 0..<5 {
            sources.selectedSegmentIndex = index
            sources.sendActions(for: .valueChanged)
            eventually("所选格式应真实播放") { player.current > 0.2 }
            let layer = try XCTUnwrap(player.view.playerLayer as? AVPlayerLayer)
            let item = layer.player?.currentItem
            let rates: UISegmentedControl = try control("video.rate", in: page.view)
            rates.selectedSegmentIndex = 2
            rates.sendActions(for: .valueChanged)
            XCTAssertEqual(player.rate, 1.5)
            let gravity: UISegmentedControl = try control("video.gravity", in: page.view)
            gravity.selectedSegmentIndex = 1
            gravity.sendActions(for: .valueChanged)
            XCTAssertEqual(layer.videoGravity, .resizeAspectFill)
            XCTAssertTrue(layer.player?.currentItem === item)
            let capture: UIButton = try control("video.capture", in: page.view)
            let snapshot: UIImageView = try control("video.snapshot", in: page.view)
            eventually("当前格式截图应显示") { capture.sendActions(for: .touchUpInside); return snapshot.image != nil }
        }
    }

    /// 页面销毁时即使会话配置尚未回调，也不能由迟到闭包保活页面或启动资源。
    func testPageReleasedDuringSessionPreparation() {
        weak var released: SimplePlayerViewController?
        var retainedPlayer: VideoPlayerable?
        autoreleasepool {
            let page = SimplePlayerViewController.instance(2)
            released = page
            page.loadViewIfNeeded()
            retainedPlayer = page.player
            page.preparePlayback()
        }
        pump(0.5)
        XCTAssertNil(released)
        XCTAssertNil(retainedPlayer?.resource)
    }

    /// 快速切回原音并更换资源，旧轨道异步结果不得污染下一资源。
    func testPageCancelsObsoleteMix() throws {
        let page = SimplePlayerViewController.instance(2)
        page.loadViewIfNeeded()
        page.preparePlayback()
        let player = try XCTUnwrap(page.player)
        defer { player.stop() }
        eventually("先开始播放") { player.current > 0.2 }
        let mix: UISegmentedControl = try control("video.mix", in: page.view)
        mix.selectedSegmentIndex = 1
        mix.sendActions(for: .valueChanged)
        mix.selectedSegmentIndex = 0
        mix.sendActions(for: .valueChanged)
        let source: UISegmentedControl = try control("video.source", in: page.view)
        source.selectedSegmentIndex = 3
        source.sendActions(for: .valueChanged)
        eventually("无音轨视频应继续播放") { player.current > 0.2 }
        pump(0.2)
        XCTAssertNil((player as? AVVideoAudioMixControlling)?.audioMix)
    }

    /// 使用可访问性标识查找实际控件；布局调整不应让测试依赖子视图顺序。
    private func control<T: UIView>(_ identifier: String, in view: UIView) throws -> T {
        if view.accessibilityIdentifier == identifier, let match = view as? T { return match }
        for child in view.subviews {
            if let match: T = try? control(identifier, in: child) { return match }
        }
        throw NSError(domain: "DemoControl", code: 1, userInfo: [NSLocalizedDescriptionKey: identifier])
    }
}
