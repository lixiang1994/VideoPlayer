//
//  SimplePlayerViewController.swift
//  Demo
//
//  Created by Lee on 2019/8/28.
//  Copyright © 2019 swift. All rights reserved.
//

import UIKit
import AVKit
import SnapKit
import VideoPlayer

class SimplePlayerViewController: UIViewController {

    private var type: Int = 0
    
    /// 页面显式持有播放器，不依赖 provider 回调闭包的间接持有。
    private(set) var player: VideoPlayerable?
    /// 网络准备和 mix 加载均校验代次，离开页面后迟到结果不得起播。
    private var generation: UInt64 = 0
    /// 会话配置期间仍可能保留旧 item，禁止把新页面选择应用到旧资源。
    private var isPreparingSession = false
    /// 当前选中素材；更换素材明确从头开始，mix / 倍速切换则保留进度。
    private var sourceURL: URL?
    /// 真实处理状态与资源来源，便于手动验证。
    private let diagnostics = UILabel()
    /// 截图输出只显示当前资源帧，不写入相册。
    private let snapshot = UIImageView()
    /// 当前选择的音轨包络，0 原始，1 固定 25%。
    private let mixControl = UISegmentedControl(items: ["原始音轨", "音量 25%"])
    /// 独立说明兼容性与应用结果，避免被周期进度刷新覆盖。
    private let mixStatus = UILabel()
    /// 网络页保留 HLS 示例，另提供文件型 MP4 验证音轨处理。
    private static let networkExamples = [
        URL(string: "https://devstreaming-cdn.apple.com/videos/wwdc/2019/808knty6w7kjssfl/808/hls_vod_mvp.m3u8")!,
        URL(string: "https://media.w3.org/2010/05/sintel/trailer.mp4")!
    ]
    /// 原有覆盖层提供者继续负责播放、暂停和拖动。
    private var provider: VideoPlayerProvider?
    private lazy var playerView = UIView()
    private lazy var statusView = UIView()
    
    /// 诊断读取真实系统 PiP 状态；不根据按钮状态推断成功。
    var isPictureInPictureActive: Bool { pip.isActive }
    var isPictureInPicturePossible: Bool { pip.pictureController?.isPictureInPicturePossible ?? false }
    /// 系统拒绝开启时保留原因，供页面与真机诊断读取。
    private(set) var pictureInPictureError: String?

    private let pip = PictureInPicture()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setup()
    }

    private func setup() {
        view.addSubview(playerView)
        
        playerView.snp.makeConstraints { (make) in
            if #available(iOS 11.0, *) {
                make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
                
            } else {
                make.top.equalTo(topLayoutGuide.snp.bottom)
            }
            make.left.right.equalToSuperview()
            make.height.equalTo(playerView.snp.width).multipliedBy(9.0 / 16.0)
        }
        
        sourceURL = type == 2 ? Bundle.main.url(forResource: "sample", withExtension: "mp4", subdirectory: "Fixtures") : Self.networkExamples[0]
        
        // 初始化播放器
        let player: VideoPlayerable
        switch type {
        case 0, 2:
            player = VideoPlayer.av.instance()
            
        default:
            #if !canImport(PLPlayerKit) || targetEnvironment(simulator)
            player = VideoPlayer.av.instance()
            #else
            player = VideoPlayer.pl.instance()
            #endif
        }
        // 简单设置
        self.player = player
        player.isLoop = false
        player.add(delegate: self)
        
        // 初始化相关视图
        let controlView = VideoPlayerControlView()
        let coverView = VideoPlayerCoverView()
        let errorView = VideoPlayerErrorView()
        let finishView = VideoPlayerFinishView()
        
        view.layoutIfNeeded()
        view.addSubview(statusView)
        statusView.addSubview(controlView)
        statusView.addSubview(coverView)
        statusView.addSubview(errorView)
        statusView.addSubview(finishView)
        
        statusView.snp.makeConstraints { (make) in
            make.edges.equalTo(playerView)
        }
        controlView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        coverView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        errorView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        finishView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        
        coverView.imageView.image = #imageLiteral(resourceName: "video_cover")
        
        let provider = VideoPlayerProvider(
            control: controlView,
            finish: finishView,
            error: errorView,
            cover: coverView
        ) { [weak self] in
            guard let self = self else { return }
            
            self.preparePlayback()
        }
        provider.set(player: player)
        self.provider = provider
        setupExamples()
    }

    /// 返回列表停止独立播放并取消准备；PiP 仅在播放页仍存在时保留前后台会话。
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent { generation &+= 1; player?.stop() }
    }

    deinit {
        generation &+= 1
        pip.close()
        player?.remove(delegate: self)
        player?.stop()
    }

    /// 本地样本与网络播放共用真实页面；会话配置完成后才准备，避免冷启动后台被系统挂起。
    func preparePlayback(url: URL? = nil) {
        if let url = url { sourceURL = url }
        guard let url = sourceURL, let player = player else { return }
        generation &+= 1
        let generation = self.generation
        isPreparingSession = true
        mixControl.selectedSegmentIndex = 0
        updateMixAvailability()
        diagnostics.text = "正在配置音频会话"
        VideoPlayer.setupAudioSession(in: .audioSession) { [weak self] in
            guard let self = self, self.generation == generation else { return }
            self.isPreparingSession = false
            let view = player.prepare(resource: AVURLAsset(url: url))
            view.backgroundColor = .black
            self.playerView.subviews.filter { $0 !== view }.forEach { $0.removeFromSuperview() }
            self.playerView.addSubview(view)
            view.snp.remakeConstraints { $0.edges.equalToSuperview() }
            self.updateMixAvailability()
            self.updateDiagnostics()
        }
    }

    /// 音轨异步加载后只更新同一 asset 的 mix，取消或切素材后不得覆盖新 item。
    @objc private func mixChanged() {
        // 示例已知使用 HLS 时不提交无效配置；不能把 item 接受 mix 当作音量实际生效。
        guard sourceURL?.pathExtension.lowercased() != "m3u8" else {
            mixControl.selectedSegmentIndex = 0
            updateMixAvailability()
            return
        }
        guard mixControl.isEnabled, let player = player, let resource = player.resource, let mixing = player as? AVVideoAudioMixControlling else { return }
        let asset = (resource as? AVURLAsset) ?? (resource as? AVVideoPlayerResource)?.asset
        guard let asset = asset else { return }
        if mixControl.selectedSegmentIndex == 0 {
            mixStatus.text = mixing.update(audioMix: nil, for: asset) ? "已恢复原始音轨" : "当前没有可更新的资源"
            return
        }
        mixStatus.text = "正在加载音轨"
        let generation = self.generation
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.generation == generation, self.mixControl.selectedSegmentIndex == 1 else { return }
                var error: NSError?
                guard asset.statusOfValue(forKey: "tracks", error: &error) == .loaded else {
                    self.mixStatus.text = "音轨加载失败：\(error?.localizedDescription ?? "未知错误")"
                    return
                }
                let tracks = asset.tracks(withMediaType: .audio)
                guard !tracks.isEmpty else {
                    self.mixControl.selectedSegmentIndex = 0
                    self.mixControl.isEnabled = false
                    self.mixStatus.text = "当前素材没有音轨，无法使用音量 mix"
                    return
                }
                let mix = AVMutableAudioMix()
                mix.inputParameters = tracks.map {
                    let parameter = AVMutableAudioMixInputParameters(track: $0)
                    parameter.setVolume(0.25, at: .zero)
                    return parameter
                }
                if mixing.update(audioMix: mix, for: asset) {
                    self.mixStatus.text = "已提交音轨 25% 配置（不改变系统音量）"
                } else {
                    self.mixControl.selectedSegmentIndex = 0
                    self.mixStatus.text = "资源已切换，忽略旧 mix"
                }
            }
        }
    }

    /// Demo 的资源地址由本页固定提供；后缀判断仅用于这些已知案例，不是通用媒体类型探测。
    private func updateMixAvailability() {
        let isHLS = sourceURL?.pathExtension.lowercased() == "m3u8"
        let supported = player is AVVideoAudioMixControlling
        mixControl.isEnabled = supported && !isHLS && !isPreparingSession && player?.resource != nil
        if isHLS {
            mixControl.selectedSegmentIndex = 0
            mixStatus.text = "HLS 不支持此 AVAudioMix 示例，请切换 MP4 测试"
        } else if !supported {
            mixStatus.text = "当前播放器后端不支持 AVAudioMix"
        } else {
            mixStatus.text = "播放文件型资源后可对比原始音轨与 25% 音量"
        }
    }

    /// 网络 HLS 与普通 HTTPS MP4 明确分开；更换资源从头开始，mix 切换仍保留播放进度。
    @objc private func networkSourceChanged(_ sender: UISegmentedControl) {
        snapshot.image = nil
        preparePlayback(url: Self.networkExamples[sender.selectedSegmentIndex])
    }

    /// 用户倍速改变只修改速率，不重新准备资源。
    @objc private func rateChanged(_ sender: UISegmentedControl) {
        player?.rate = [0.5, 1, 1.5, 2][sender.selectedSegmentIndex]
        // 暂停时没有周期进度反馈，目标选择也需要立即刷新，但不能启动播放。
        updateDiagnostics()
    }

    /// 填充模式只影响画面层，不改变视频时钟。
    @objc private func gravityChanged(_ sender: UISegmentedControl) { player?.view.contentMode = [.scaleAspectFit, .scaleAspectFill, .scaleToFill][sender.selectedSegmentIndex] }

    /// 更换测试文件会显式重播；不同格式与无音轨素材用于观察实际支持情况。
    @objc private func sourceChanged(_ sender: UISegmentedControl) {
        let names = ["sample", "sample", "hevc", "silent", "rotated"]
        sourceURL = Bundle.main.url(forResource: names[sender.selectedSegmentIndex], withExtension: sender.selectedSegmentIndex == 1 ? "mov" : "mp4", subdirectory: "Fixtures")
        snapshot.image = nil
        preparePlayback()
    }

    /// 截图回调会校验资源代次；停止或切素材后不展示旧截图。
    @objc private func capture() {
        let generation = self.generation
        player?.screenshot { [weak self] image in
            guard let self = self, self.generation == generation else { return }
            self.snapshot.image = image
            if image == nil { self.diagnostics.text = "当前尚无可用视频帧，请播放后重试" }
        }
    }

    /// 页面提供可直接验证的格式、画面模式、音轨 mix、倍速和截图案例。
    private func setupExamples() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        let scroll = UIScrollView()
        view.addSubview(scroll)
        scroll.snp.makeConstraints { make in
            make.top.equalTo(playerView.snp.bottom).offset(16)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }
        scroll.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(scroll.contentLayoutGuide).inset(16)
            make.width.equalTo(scroll.frameLayoutGuide).offset(-32)
        }
        diagnostics.numberOfLines = 0
        diagnostics.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        diagnostics.accessibilityIdentifier = "video.diagnostics"
        stack.addArrangedSubview(diagnostics)
        if type == 2 {
            let sources = UISegmentedControl(items: ["MP4 有声", "MOV", "HEVC", "无音轨", "竖拍"])
            sources.accessibilityIdentifier = "video.source"
            sources.selectedSegmentIndex = 0
            sources.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)
            stack.addArrangedSubview(sources)
        }
        if type == 0 {
            let sources = UISegmentedControl(items: ["HLS（不支持 mix）", "MP4（测试 mix）"])
            sources.accessibilityIdentifier = "video.networkSource"
            sources.selectedSegmentIndex = 0
            sources.addTarget(self, action: #selector(networkSourceChanged), for: .valueChanged)
            stack.addArrangedSubview(sources)
        }
        let rates = UISegmentedControl(items: ["0.5×", "1×", "1.5×", "2×"])
        rates.accessibilityIdentifier = "video.rate"
        rates.selectedSegmentIndex = 1
        rates.addTarget(self, action: #selector(rateChanged), for: .valueChanged)
        stack.addArrangedSubview(rates)
        let gravity = UISegmentedControl(items: ["完整显示", "填充裁剪", "拉伸"])
        gravity.accessibilityIdentifier = "video.gravity"
        gravity.selectedSegmentIndex = 0
        gravity.addTarget(self, action: #selector(gravityChanged), for: .valueChanged)
        stack.addArrangedSubview(gravity)
        mixControl.accessibilityIdentifier = "video.mix"
        mixControl.selectedSegmentIndex = 0
        mixControl.addTarget(self, action: #selector(mixChanged), for: .valueChanged)
        stack.addArrangedSubview(mixControl)
        mixStatus.numberOfLines = 0
        mixStatus.font = .systemFont(ofSize: 13)
        mixStatus.accessibilityIdentifier = "video.mixStatus"
        stack.addArrangedSubview(mixStatus)
        updateMixAvailability()
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "video.capture"
        button.setTitle("截图（仅展示，不保存相册）", for: .normal)
        button.addTarget(self, action: #selector(capture), for: .touchUpInside)
        stack.addArrangedSubview(button)
        snapshot.accessibilityIdentifier = "video.snapshot"
        snapshot.contentMode = .scaleAspectFit
        snapshot.snp.makeConstraints { $0.height.equalTo(100) }
        stack.addArrangedSubview(snapshot)
        updateDiagnostics()
    }

    /// 显示资源类型、媒体时间与速率目标；保存的 rate 不能冒充媒体时钟实测。
    private func updateDiagnostics() {
        guard let player = player else { return }
        diagnostics.text = String(format: "%@ · %@ · %.1f / %.1f 秒 · 目标 %.1f×", sourceURL?.isFileURL == true ? "本地" : "网络", playbackStatus, player.current, player.duration, player.rate)
    }

    /// 资源状态和控制反馈分开显示；加载时即使目标倍率非零也不宣称已经播放。
    private var playbackStatus: String {
        guard let player = player else { return "未准备" }
        switch player.state {
        case .stopped: return "已停止"
        case .prepare: return "准备中"
        case .finished: return "已结束"
        case .failed: return "播放失败"
        case .playing:
            if player.loading != .ended { return "缓冲中" }
            return player.control == .playing ? "播放中" : "已暂停"
        }
    }

    func videoPlayer(_ player: VideoPlayerable, updatedCurrent time: Double) { updateDiagnostics() }

    /// 等待数据可能不伴随媒体进度回调，必须单独刷新缓冲状态。
    func videoPlayerLoadingState(_ player: VideoPlayerable, state: VideoPlayer.LoadingState) { updateDiagnostics() }

    
    private static func instance() -> Self {
        return StoryBoard.main.instance()
    }
    
    static func instance(_ type: Int) -> Self {
        let controller = instance()
        controller.type = type
        return controller
    }
}

extension SimplePlayerViewController {
    
    @objc
    func startPictureAction() {
        pip.start()
    }
    
    @objc
    private func stopPictureAction() {
        pip.stop()
    }
}

extension SimplePlayerViewController: VideoPlayerDelegate {
    
    func videoPlayerControlState(_ player: VideoPlayerable, state: VideoPlayer.ControlState) {
        pip.invalidatePlaybackState()
        updateDiagnostics()
    }
    
    func videoPlayerState(_ player: VideoPlayerable, state: VideoPlayer.State) {
        updateDiagnostics()
        switch state {
        case .playing:
            guard
                pip.isSuspended,
                let layer = player.view.playerLayer as? AVPlayerLayer else {
                return
            }
            // 播放中时 设置画中画
            pip.setup(player: layer)
            pip.delegate = self
            
            if #available(iOS 14.0, *) {
                navigationItem.rightBarButtonItem = UIBarButtonItem(
                    image: AVPictureInPictureController.pictureInPictureButtonStartImage,
                    style: .plain,
                    target: self,
                    action: #selector(startPictureAction)
                )
            }
            
        case .finished, .stopped, .failed:
            // 不在播放中时 则关闭画中画
            pip.close()
            
            navigationItem.rightBarButtonItem = nil
            
        default:
            break
        }
    }
}

extension SimplePlayerViewController: AVPictureInPictureControllerDelegate {
    
    /// 系统可能因为会话、画面尚未就绪或后台策略拒绝 PiP，不能把请求当作启动成功。
    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        pictureInPictureError = error.localizedDescription
        diagnostics.text = "画中画开启失败：\(error.localizedDescription)"
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pictureInPictureError = nil
        // 真实开启后清除先前被系统拒绝的错误，并隐藏覆盖层。
        statusView.isHidden = true
        
        if #available(iOS 14.0, *) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: AVPictureInPictureController.pictureInPictureButtonStopImage,
                style: .plain,
                target: self,
                action: #selector(stopPictureAction)
            )
        }
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // 将要停止PictureInPicture的代理方法
        // 显示视图
        statusView.isHidden = false
        
        if #available(iOS 14.0, *) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: AVPictureInPictureController.pictureInPictureButtonStartImage,
                style: .plain,
                target: self,
                action: #selector(startPictureAction)
            )
        }
    }
    
    /// Demo 不持有全局页面恢复路由；仅当前界面仍在窗口中时确认恢复成功。
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(isViewLoaded && view.window != nil)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // 已经停止PictureInPicture的代理方法
        // 停止播放器
        if pip.isPictureClose { provider?.player?.stop() }
    }
}
