import XCTest
import AVKit
@testable import VideoPlayer
@testable import Demo

/// 通过页面实际控件验证资源身份、异步准备和界面选项，不只验证播放器底层接口。
final class DemoIntegrationTests: PlaybackTestCase {
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
