#if DEBUG
import AVKit
import VideoPlayer

/// 仅显式设置 VIDEO_DEVICE_DIAGNOSTICS=1 时启用，记录真实页面、PiP 与系统前后台事件。
/// 此入口不注入生命周期通知，也不把请求开启当作系统已开启。
final class VideoDeviceDiagnostics {
    /// 持有实际 Demo 播放页，播放实现与手动入口一致。
    private let page = SimplePlayerViewController.instance(2)
    /// 仅前台或系统允许后台运行时采样；回前台仍通过事件计算媒体时间差。
    private var timer: Timer?
    /// 生命周期监听令牌，销毁时归还。
    private var observers: [NSObjectProtocol] = []
    /// 保存事件时刻的媒体位置与 PiP 状态，避免只观察最终值。
    private var events: [[String: Any]] = []
    /// 自动请求仅供系统 PiP 诊断；导航回归关闭它，避免异步 PiP 干扰返回路径。
    private let requestsPictureInPicture: Bool
    /// 本轮诊断只请求一次 PiP，拒绝后保留失败原因。
    private var requestedPiP = false
    /// 已取到的实际截图尺寸。
    private var frameSize = ""

    /// 原始 storyboard 窗口由 Scene 提供；保留列表作为返回目标，诊断使用长视频。
    /// requestsPictureInPicture 默认开启，导航测试显式关闭，不改变正常 PiP 诊断行为。
    init(window: UIWindow, requestsPictureInPicture: Bool = true) {
        self.requestsPictureInPicture = requestsPictureInPicture
        // 不能仅把播放页包装成导航根页面，否则仍然没有上一页可返回。
        // 独立测试窗口没有初始导航时，补齐与正常启动一致的 storyboard 列表。
        let navigation = window.rootViewController as? UINavigationController
            ?? UIStoryboard(name: "Main", bundle: .main).instantiateInitialViewController() as! UINavigationController
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.pushViewController(page, animated: false)
        page.loadViewIfNeeded()
        let url = Bundle.main.url(forResource: "long", withExtension: "mp4", subdirectory: "Fixtures")!
        page.preparePlayback(url: url)
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self = self else { return }
                self.events.append(["event": note.name.rawValue, "current": self.page.player?.current ?? 0, "time": Date().timeIntervalSince1970, "pip": self.page.isPictureInPictureActive])
                self.refresh()
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// 只写诊断文件，读取到的时间与画面均来自真实播放器，不修改其内部状态。
    private func refresh() {
        guard let player = page.player else { return }
        if requestsPictureInPicture, player.current > 2, page.isPictureInPicturePossible, !requestedPiP {
            requestedPiP = true
            page.startPictureAction()
        }
        if frameSize.isEmpty, player.current > 1 {
            player.screenshot { [weak self] image in
                if let image = image { self?.frameSize = "\(Int(image.size.width))x\(Int(image.size.height))" }
            }
        }
        let layer = player.view.playerLayer as? AVPlayerLayer
        let record: [String: Any] = [
            "current": player.current,
            "applicationState": UIApplication.shared.applicationState.rawValue,
            "sceneActivationState": page.view.window?.windowScene?.activationState.rawValue ?? -1,
            "control": player.control == .playing ? "playing" : "paused",
            "readyForDisplay": layer?.isReadyForDisplay ?? false,
            "pipPossible": page.isPictureInPicturePossible,
            "pipActive": page.isPictureInPictureActive,
            "pipRequested": requestedPiP,
            "pipError": page.pictureInPictureError ?? "",
            "frameSize": frameSize,
            "events": events,
            "timestamp": Date().timeIntervalSince1970
        ]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("video-diagnostics.json")
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
#endif
