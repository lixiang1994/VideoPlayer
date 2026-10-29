//
//  AVVideoPlayer.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//

import UIKit
import AVFoundation
import CoreImage

public extension VideoPlayer {
    
    static let av: Builder = .init { AVVideoPlayer($0) }
}

/// AVPlayer 视频后端；公开操作和属性访问限定在主线程，系统异步事件统一回到主线程消费。
class AVVideoPlayer: NSObject {
    
    /// 当前资源；停止或失败后清空。
    private(set) var resource: VideoPlayerURLAsset?
    /// 创建实例时确定的播放配置。
    private(set) var configuration: VideoPlayerConfiguration
    /// 资源生命周期；playing 沿用原语义，表示资源已就绪，并不代表正在出声。
    private(set) var state: VideoPlayer.State = .stopped {
        didSet {
            stateGeneration &+= 1
            let stateGeneration = self.stateGeneration
            let value = state
            notify(while: { self.stateGeneration == stateGeneration }) { $0.videoPlayerState(self, state: value) }
        }
    }
    /// 实际播放控制状态，资源清理时恢复为暂停。
    private(set) var control: VideoPlayer.ControlState = .pausing {
        didSet {
            guard oldValue != control else { return }
            let value = control
            notify(while: { self.control == value }) { $0.videoPlayerControlState(self, state: value) }
        }
    }
    /// 当前是否等待媒体数据，与用户的播放意图分开维护。
    private(set) var loading: VideoPlayer.LoadingState = .ended {
        didSet {
            guard oldValue != loading else { return }
            let value = loading
            notify(while: { self.loading == value }) { $0.videoPlayerLoadingState(self, state: value) }
        }
    }
    /// 用户选择的播放速率；暂停期间只保存设置，不启动播放。
    var rate: Double = 1.0 {
        didSet {
            guard rate.isFinite, Float(rate).isFinite, Float(rate) > 0 else {
                rate = oldValue
                return
            }
            guard case .playing = state, intendedToPlay, seekRequest == nil, !isInterrupted else { return }
            applyPlaybackIntent()
        }
    }
    /// 音量范围为 0 到 1，不提供额外增益。
    var volume: Double = 1.0 {
        didSet {
            player.volume = .init(volume)
        }
    }
    /// 静音设置不改变播放意图。
    var isMuted: Bool = false {
        didSet {
            player.isMuted = isMuted
        }
    }
    /// 开启后在播放结束时寻回起点，沿用当前播放意图。
    var isLoop: Bool = false
    
    #if os(iOS)
    /// 是否允许后台播放；禁止时保留播放意图，回到前台再恢复。
    var allowedBackgroundPlayback: Bool = true
    /// 由生命周期通知维护；willEnterForeground 到达时 applicationState 仍可能是 background。
    private var isInBackground = UIApplication.shared.applicationState == .background
    /// 准备阶段使用的短期后台任务，结束准备或清理资源时必须归还。
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    #endif
    
    /// 多播代理使用弱引用，避免播放器与业务层互相持有。
    var delegates: [VideoPlayerDelegateBridge<AnyObject>] = []
    /// 生命周期内复用同一个 AVPlayer，观察者也始终从所属的实例移除。
    private let player: AVPlayer
    /// 周期进度回调令牌，释放实例前必须显式移除。
    private var playerTimeObserver: Any?
    /// 画面层与播放器一样复用，避免切资源后 PiP 或调用方仍指向过期播放器。
    private lazy var playerLayer = AVPlayerLayer(player: player)
    /// 同一个实例始终返回同一视图；外部布局、contentMode 与 PiP 绑定不会因切资源失效。
    private lazy var playerView: VideoPlayerView = makePlayerView()
    /// 当前 item 的视频输出；清理时主动解除绑定，截图不能读取上一资源的帧。
    private var playerOutput: AVPlayerItemVideoOutput?
    /// 图像上下文可复用；截图在主线程返回当前已解码帧，不进行额外网络寻时。
    private let imageContext = CIContext()
    /// 每次切资源或停止时递增，隔离已排队的旧资源回调。
    private var generation: UInt64 = 0
    /// 当前有效的寻时请求；对象身份用于隔离被取消请求的迟到回调。
    private var seekRequest: VideoPlayerSeekRequest?
    /// 状态广播可同步触发下一状态，代次防止后续代理收到过期的生命周期事件。
    private var stateGeneration: UInt64 = 0
    /// 同一资源内每次有效 seek 递增，隔离代理重入后已经过期的寻时事件。
    private var seekGeneration: UInt64 = 0
    /// 用户希望播放的状态，不等同于底层瞬时 rate。
    private var intendedToPlay: Bool = false
    /// 音频会话中断期间禁止自动恢复，结束时还需检查系统的 shouldResume。
    private var isInterrupted: Bool = false
    /// 已完成寻时的实际位置，用于短暂屏蔽底层进度回退；切资源时清空。
    private var currentTimeCalibrator: TimeInterval?
    /// 仅保留最近一次连续卡顿的记录，避免历史卡顿累计触发失败。
    private var itemPlaybackStalledRecords: [Double] = []
    /// 播放器实际控制状态的观察令牌。
    private var timeControlStatusObservation: NSKeyValueObservation?
    /// 资源状态保持全程监听，包含 readyToPlay 之后的 failed。
    private var itemStatusObservation: NSKeyValueObservation?
    /// 总时长变化的观察令牌。
    private var itemDurationObservation: NSKeyValueObservation?
    /// 已加载时间段的观察令牌。
    private var itemLoadedTimeRangesObservation: NSKeyValueObservation?
    /// 缓冲可持续播放状态的观察令牌。
    private var itemPlaybackLikelyToKeepUpObservation: NSKeyValueObservation?
    /// 当前资源的 block 通知令牌，销毁时统一注销。
    private var itemNotifications: [NSObjectProtocol] = []
    
    /// 默认使用系统播放器；允许内部注入播放器以验证取消回调等确定性时序。
    init(_ configuration: VideoPlayerConfiguration, player: AVPlayer = AVPlayer()) {
        self.configuration = configuration
        self.player = player
        super.init()
        setupNotification()
    }
    
    deinit {
        // 不向代理广播销毁过程，避免回调重新进入正在析构的实例。
        removeObserver()
        removeNotification()
        NotificationCenter.default.removeObserver(self)
        playerLayer.player = nil
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        player.currentItem?.asset.cancelLoading()
        player.replaceCurrentItem(with: nil)
        seekRequest?.complete(false)
        #if os(iOS)
        endBackgroundTask()
        #endif
    }
    
    /// 注册与资源无关的系统通知；资源通知单独绑定具体 item。
    private func setupNotification() {
        if configuration.handlesAudioSessionNotifications {
            NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruption), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
            NotificationCenter.default.addObserver(self, selector: #selector(routeChanged), name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
            NotificationCenter.default.addObserver(self, selector: #selector(mediaServicesWereReset), name: AVAudioSession.mediaServicesWereResetNotification, object: AVAudioSession.sharedInstance())
        }
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        #endif
    }
}

extension AVVideoPlayer {
    
    /// 每个代理调用前重新校验；除资源切换外，调用方也可隔离同一资源内已被覆盖的事件。
    private func notify(while isValid: () -> Bool = { true }, _ action: (VideoPlayerDelegate) -> Void) {
        let generation = self.generation
        delegate {
            guard self.generation == generation, isValid() else { return }
            action($0)
        }
    }

    /// KVO 可能在非主线程触发；异步消费同时避免注册观察者时同步重入。
    private func receive(_ item: AVPlayerItem, action: @escaping (AVVideoPlayer) -> Void) {
        DispatchQueue.main.async { [weak self, weak item] in
            guard let self = self, let item = item, self.player.currentItem === item else { return }
            action(self)
        }
    }

    /// 失败前先使旧回调失效；取消请求的业务回调若切换资源，不再覆盖新状态。
    private func error(_ value: Swift.Error?) {
        let generation = clear()
        guard self.generation == generation else { return }
        control = .pausing
        guard self.generation == generation else { return }
        loading = .ended
        guard self.generation == generation else { return }
        state = .failed(value)
    }

    /// 清理资源但不广播中间状态；先使异步操作失效，再取消底层请求。
    @discardableResult
    private func clear() -> UInt64 {
        generation &+= 1
        let generation = self.generation
        let request = seekRequest
        seekRequest = nil
        removeObserver()
        removeNotification()
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        player.currentItem?.asset.cancelLoading()
        if let output = playerOutput { player.currentItem?.remove(output) }
        playerOutput = nil
        player.replaceCurrentItem(with: nil)
        resource = nil
        intendedToPlay = false
        // 会话中断属于整个播放器，切资源不能清掉尚未结束的中断。
        currentTimeCalibrator = nil
        itemPlaybackStalledRecords = []
        #if os(iOS)
        endBackgroundTask()
        #endif
        // 回调可能同步准备另一资源，因此调用方必须检查返回的资源代次。
        request?.complete(false)
        return generation
    }
    
    /// 为当前资源注册播放时钟和控制状态，回调始终校验 item 身份。
    private func addObserver(item: AVPlayerItem) {
        let frequency = Swift.max(1, Swift.min(configuration.currentTimeCallbackPeriodicInterval, UInt(Int32.max)))
        let interval = CMTime(value: 1, timescale: CMTimeScale(frequency))
        playerTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak item] _ in
            guard let self = self, let item = item, self.player.currentItem === item else { return }
            guard case .playing = self.state else { return }
            let current = self.current
            self.notify { $0.videoPlayer(self, updatedCurrent: current) }
        }
        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak item] _, _ in
            guard let item = item else { return }
            self?.receive(item) { $0.updatePlaybackState() }
        }
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            self?.receive(item) { $0.itemStatusChanged(item) }
        }
        itemDurationObservation = item.observe(\.duration, options: [.new, .old]) { [weak self] item, change in
            guard change.newValue != change.oldValue else { return }
            self?.receive(item) { engine in
                let duration = engine.duration
                engine.notify { $0.videoPlayer(engine, updatedDuration: duration) }
            }
        }
        itemLoadedTimeRangesObservation = item.observe(\.loadedTimeRanges, options: [.new, .old]) { [weak self] item, change in
            guard change.newValue != change.oldValue else { return }
            self?.receive(item) { engine in
                let buffer = engine.buffer
                engine.notify { $0.videoPlayer(engine, updatedBuffer: buffer) }
            }
        }
        itemPlaybackLikelyToKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .old]) { [weak self] item, change in
            guard change.newValue != change.oldValue else { return }
            self?.receive(item) { $0.updatePlaybackState() }
        }
    }

    /// 先移除周期回调，再释放 KVO 令牌；停止后允许安全重复调用。
    private func removeObserver() {
        if let observer = playerTimeObserver {
            playerTimeObserver = nil
            player.removeTimeObserver(observer)
        }
        timeControlStatusObservation = nil
        itemStatusObservation = nil
        itemDurationObservation = nil
        itemLoadedTimeRangesObservation = nil
        itemPlaybackLikelyToKeepUpObservation = nil
    }
    
    /// 就绪只推进一次生命周期，后续仍保留失败监听。
    private func itemStatusChanged(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            guard case .prepare = state else { return }
            let generation = self.generation
            #if os(iOS)
            endBackgroundTask()
            #endif
            state = .playing
            guard self.generation == generation, player.currentItem === item else { return }
            if let request = seekRequest {
                // 代理可在 ready 回调内创建 seek；已开始的请求不能重复启动。
                if !request.hasBegan { startSeek(request, item: item) }
            } else {
                applyPlaybackIntent()
            }
        case .failed:
            error(item.error)
        default:
            break
        }
    }

    /// 根据实际控制状态派发事件，不在状态观察回调内反复修改播放速率。
    private func updatePlaybackState() {
        guard case .playing = state else { return }
        let generation = self.generation
        // pause 后系统状态可能迟到；后台限制和用户意图都必须优先于瞬时 timeControlStatus。
        control = isPlaybackPermitted && player.timeControlStatus == .playing ? .playing : .pausing
        guard self.generation == generation else { return }
        // control 代理可能同步暂停、seek 或改变后台策略，因此这里重新读取许可，不能缓存旧值。
        loading = isPlaybackPermitted && player.timeControlStatus == .waitingToPlayAtSpecifiedRate ? .began : .ended
    }

    /// 控制状态和起播共用同一许可条件，每次读取都反映代理重入后的最新意图及策略。
    private var isPlaybackPermitted: Bool {
        #if os(iOS)
        guard allowedBackgroundPlayback || !isInBackground else { return false }
        #endif
        return intendedToPlay && !isInterrupted && seekRequest == nil
    }

    /// 恢复播放只消费当前意图；中断和后台策略优先于自动播放。
    private func applyPlaybackIntent() {
        guard case .playing = state, seekRequest == nil else { return }
        let generation = self.generation
        if isPlaybackPermitted {
            player.playImmediately(atRate: .init(rate))
        } else {
            player.pause()
        }
        guard self.generation == generation else { return }
        updatePlaybackState()
    }

    /// 通知绑定当前 item，迟到的通知与 KVO 使用相同的身份校验。
    private func addNotification(item: AVPlayerItem) {
        let handlers: [(Notification.Name, (AVVideoPlayer, Notification) -> Void)] = [
            (.AVPlayerItemPlaybackStalled, { $0.itemPlaybackStalled($1) }),
            (.AVPlayerItemDidPlayToEndTime, { $0.itemDidPlayToEndTime($1) }),
            (.AVPlayerItemFailedToPlayToEndTime, { $0.itemFailedToPlayToEndTime($1) })
        ]
        for (name, handler) in handlers {
            let token = NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self, weak item] notification in
                guard let self = self, let item = item, self.player.currentItem === item else { return }
                handler(self, notification)
            }
            itemNotifications.append(token)
        }
    }
    
    /// block 通知不会随 weak self 自动注销，必须显式移除令牌。
    private func removeNotification() {
        itemNotifications.forEach { NotificationCenter.default.removeObserver($0) }
        itemNotifications = []
    }
}

extension AVVideoPlayer {
    
    /// 连续卡顿重试不改变用户意图；历史中断不计入新的连续窗口。
    private func itemPlaybackStalled(_ notification: Notification) {
        guard case .playing = state, intendedToPlay, !isInterrupted else { return }
        let now = Date().timeIntervalSince1970
        if let last = itemPlaybackStalledRecords.last, now - last >= 1 {
            itemPlaybackStalledRecords = []
        }
        itemPlaybackStalledRecords.append(now)
        if itemPlaybackStalledRecords.count >= 11 {
            error(NSError(domain: "Playback Stalled", code: -111111))
        } else {
            applyPlaybackIntent()
        }
    }
    
    /// 循环通过 seek 恢复；普通结束保留资源，允许再次 play 从头播放。
    private func itemDidPlayToEndTime(_ notification: Notification) {
        guard case .playing = state, seekRequest == nil else { return }
        if isLoop {
            seek(to: .init(time: .zero))
        } else {
            let generation = self.generation
            pause()
            guard self.generation == generation else { return }
            state = .finished
        }
    }
    
    /// 保留系统提供的具体错误，供业务层决定是否重试或切换后端。
    private func itemFailedToPlayToEndTime(_ notification: Notification) {
        error(notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
    }
    
    /// 系统会话通知可能来自其他线程，统一回主线程并尊重系统恢复许可。
    @objc
    private func sessionInterruption(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let info = notification.userInfo,
                  let value = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
            switch type {
            case .began:
                self.isInterrupted = true
                self.player.pause()
                self.updatePlaybackState()
            case .ended:
                guard self.isInterrupted else { return }
                self.isInterrupted = false
                let raw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if !AVAudioSession.InterruptionOptions(rawValue: raw).contains(.shouldResume) {
                    self.intendedToPlay = false
                }
                self.applyPlaybackIntent()
            @unknown default:
                break
            }
        }
    }

    /// 耳机或蓝牙输出断开时暂停，避免突然从扬声器继续播放。
    @objc
    private func routeChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable else { return }
            self?.pause()
        }
    }

    /// 音频服务重置后显式报告失败，由业务层重新配置会话和资源。
    @objc
    private func mediaServicesWereReset(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.player.currentItem != nil else { return }
            self.error(NSError(domain: "VideoPlayer.MediaServicesReset", code: -1))
        }
    }
}

#if os(iOS)
extension AVVideoPlayer {

    /// 归还后台任务，先清空标识，避免重复结束同一任务。
    private func endBackgroundTask() {
        guard backgroundTaskIdentifier != .invalid else { return }
        let identifier = backgroundTaskIdentifier
        backgroundTaskIdentifier = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }

    /// 回前台时仅恢复仍然有效的播放意图。
    @objc
    private func willEnterForeground(_ notification: Notification) {
        // 先解除后台限制，再消费意图；此时不能依赖 UIApplication 的旧状态。
        isInBackground = false
        endBackgroundTask()
        applyPlaybackIntent()
    }

    /// 后台任务仅保护准备阶段，不能替代宿主的音频后台模式配置。
    @objc
    private func didEnterBackground(_ notification: Notification) {
        isInBackground = true
        guard player.currentItem != nil else { return }
        switch state {
        case .prepare where allowedBackgroundPlayback:
            guard backgroundTaskIdentifier == .invalid else { return }
            backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.endBackgroundTask()
            }
        case .playing where !allowedBackgroundPlayback:
            player.pause()
            updatePlaybackState()
        default:
            break
        }
    }
}
#endif

extension AVVideoPlayer: VideoPlayerable {
    
    @discardableResult
    func prepare(resource: VideoPlayerURLAsset) -> VideoPlayerView {
        let generation = clear()
        guard self.generation == generation else { return playerView }
        // 专用资源必须复用构建 mix 时的 asset，避免重建后丢失加载选项或音轨绑定。
        let avResource = resource as? AVVideoPlayerResource
        let asset = avResource?.asset ?? (resource as? AVURLAsset) ?? AVURLAsset(url: resource.value)
        let item = AVPlayerItem(asset: asset)
        // 在 item 交给 AVPlayer 之前安装配置；普通资源显式使用 nil，不继承上一首的处理。
        item.audioMix = avResource?.audioMix
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.preferredForwardBufferDuration = configuration.preferredBufferDuration
        item.audioTimePitchAlgorithm = .spectral
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        playerOutput = output
        self.resource = resource
        intendedToPlay = configuration.isAutoplay
        player.actionAtItemEnd = .pause
        player.volume = .init(volume)
        player.isMuted = isMuted
        player.automaticallyWaitsToMinimizeStalling = false
        // 非零 rate 会直接请求播放；准备阶段保持暂停，等观察者建立后再消费自动播放意图。
        player.replaceCurrentItem(with: item)
        addObserver(item: item)
        addNotification(item: item)
        control = .pausing
        guard self.generation == generation else { return playerView }
        loading = .began
        guard self.generation == generation else { return playerView }
        state = .prepare
        return playerView
    }
    
    func play() {
        switch state {
        case .prepare:
            intendedToPlay = true
        case .playing:
            intendedToPlay = true
            applyPlaybackIntent()
        case .finished:
            let generation = self.generation
            intendedToPlay = true
            state = .playing
            guard self.generation == generation else { return }
            if let request = seekRequest {
                if let item = player.currentItem, !request.hasBegan { startSeek(request, item: item) }
            } else {
                seek(to: .init(time: .zero))
            }
        default:
            break
        }
    }
    
    func pause() {
        intendedToPlay = false
        player.pause()
        updatePlaybackState()
    }
    
    func stop() {
        let generation = clear()
        guard self.generation == generation else { return }
        control = .pausing
        guard self.generation == generation else { return }
        loading = .ended
        guard self.generation == generation else { return }
        state = .stopped
    }
    
    func seek(to target: VideoPlayer.Seek) {
        guard let item = player.currentItem, target.time.isFinite else {
            target.completion?(false)
            return
        }
        let generation = self.generation
        seekGeneration &+= 1
        let previous = seekRequest
        let request = VideoPlayerSeekRequest(target)
        // 先发布新请求，再取消旧请求；cancelPendingSeeks 仍可能调用旧 completion。
        seekRequest = request
        currentTimeCalibrator = nil
        item.cancelPendingSeeks()
        previous?.complete(false)
        guard self.generation == generation, seekRequest === request else { return }
        guard item.status == .readyToPlay else { return }
        switch state {
        case .playing:
            break
        case .finished:
            // 重开已就绪生命周期，保留 EOF 后的暂停意图；状态代理可能同步取消或覆盖请求。
            state = .playing
            guard self.generation == generation, seekRequest === request else { return }
        default:
            return
        }
        startSeek(request, item: item)
    }

    /// ready 前的 seek 与播放中的 seek 共用同一路径，并只对当前请求应用结果。
    private func startSeek(_ request: VideoPlayerSeekRequest, item: AVPlayerItem) {
        guard !request.hasBegan, seekRequest === request else { return }
        request.hasBegan = true
        let generation = self.generation
        let target = request.target
        let seekGeneration = self.seekGeneration
        player.pause()
        updatePlaybackState()
        guard self.generation == generation, seekRequest === request else { return }
        // 目标显示仍保留原有行为；完成后只采用底层实际到达的位置。
        notify(while: { self.seekRequest === request }) { $0.videoPlayer(self, updatedCurrent: target.time) }
        guard self.generation == generation, seekRequest === request else { return }
        notify(while: { self.seekRequest === request }) { $0.videoPlayer(self, seekBegan: target) }
        guard self.generation == generation, seekRequest === request else { return }
        let seconds = boundedSeekTime(target.time, item: item)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
            DispatchQueue.main.async {
                guard let self = self, let item = item,
                      self.generation == generation, self.player.currentItem === item,
                      self.seekRequest === request else {
                    request.complete(false)
                    return
                }
                self.seekRequest = nil
                let current = item.currentTime().seconds
                self.currentTimeCalibrator = finished && current.isFinite ? current : nil
                // 先完成内部状态，再调用业务 completion；业务可在回调里继续 seek、切资源或暂停。
                request.complete(finished)
                guard self.generation == generation, self.seekGeneration == seekGeneration, self.seekRequest == nil else { return }
                // 第一个代理可能开始新 seek，后续代理不能再收到旧请求的结束事件。
                self.notify(while: { self.seekGeneration == seekGeneration }) { $0.videoPlayer(self, seekEnded: target) }
                guard self.generation == generation, self.seekGeneration == seekGeneration, self.seekRequest == nil else { return }
                self.applyPlaybackIntent()
            }
        }
    }
    
    /// 点播限制在有效时长内；直播优先限制在实际可寻时窗口，避免使用 indefinite duration。
    private func boundedSeekTime(_ seconds: TimeInterval, item: AVPlayerItem) -> TimeInterval {
        let ranges = item.seekableTimeRanges.map { $0.timeRangeValue }.filter {
            $0.start.seconds.isFinite && $0.end.seconds.isFinite
        }
        if ranges.contains(where: { seconds >= $0.start.seconds && seconds <= $0.end.seconds }) {
            return seconds
        }
        if !ranges.isEmpty {
            return ranges.flatMap { [$0.start.seconds, $0.end.seconds] }.min { abs($0 - seconds) < abs($1 - seconds) } ?? 0
        }
        let duration = item.duration.seconds
        return duration.isFinite ? Swift.min(Swift.max(0, seconds), Swift.max(0, duration)) : Swift.max(0, seconds)
    }
    
    /// 构建一次输出视图；闭包只引用画面层，不反向持有播放器。
    private func makePlayerView() -> VideoPlayerView {
        let layer = playerLayer
        layer.masksToBounds = true
        let view = VideoPlayerView(layer)
        view.observe { [weak layer] (size, animation) in
            CATransaction.begin()
            CATransaction.setDisableActions(animation == nil)
            if let animation = animation {
                CATransaction.setAnimationDuration(animation.duration)
                CATransaction.setAnimationTimingFunction(animation.timingFunction)
            }
            layer?.frame = CGRect(origin: .zero, size: size)
            CATransaction.commit()
        }
        view.observe { [weak layer] (mode) in
            switch mode {
            case .scaleToFill: layer?.videoGravity = .resize
            case .scaleAspectFit: layer?.videoGravity = .resizeAspect
            default: layer?.videoGravity = .resizeAspectFill
            }
        }
        view.contentMode = .scaleAspectFit
        return view
    }

    /// 输出视图与画面层跨资源复用；停止仅清空 item，不让调用方持有的视图继续保留旧资源。
    var view: VideoPlayerView { playerView }

    /// 无 item、无视频轨或尚无可用解码帧时返回 nil；调用方应在真实播放后请求截图。
    func screenshot(completion: @escaping (UIImage?) -> Void) {
        guard let item = player.currentItem, let output = playerOutput,
              let buffer = output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: nil) else {
            completion(nil)
            return
        }
        guard let track = item.tracks.compactMap({ $0.assetTrack }).first(where: { $0.mediaType == .video }) else {
            completion(nil)
            return
        }
        let generation = self.generation
        // preferredTransform 不随 item ready 保证已加载；异步读取，避免网络素材阻塞主线程。
        track.loadValuesAsynchronously(forKeys: ["preferredTransform"]) { [weak self] in
            DispatchQueue.main.async {
                // 请求期间停止、切资源或销毁时仍完成一次，但不能返回旧资源画面。
                guard let self = self, self.generation == generation, self.player.currentItem === item,
                      track.statusOfValue(forKey: "preferredTransform", error: nil) == .loaded else {
                    completion(nil)
                    return
                }
                let image = CIImage(cvPixelBuffer: buffer).transformed(by: track.preferredTransform)
                guard let result = self.imageContext.createCGImage(image, from: image.extent) else { completion(nil); return }
                completion(UIImage(cgImage: result))
            }
        }
    }

    var current: TimeInterval {
        guard let item = player.currentItem else { return 0 }
        if let request = seekRequest { return request.target.time }
        let time = item.currentTime().seconds
        if let calibrator = currentTimeCalibrator, calibrator > time { return calibrator }
        currentTimeCalibrator = nil
        return time.isFinite ? time : 0
    }
    
    var duration: TimeInterval {
        let time = player.currentItem?.duration.seconds ?? 0
        return time.isFinite ? time : 0
    }
    
    var buffer: Double {
        guard let item = player.currentItem, duration > 0 else { return 0 }
        let end = item.loadedTimeRanges.map { $0.timeRangeValue.end.seconds }.filter { $0.isFinite }.max() ?? 0
        return Swift.min(1, Swift.max(0, end / duration))
    }
}

extension AVVideoPlayer: VideoPlayerDelegates {
    
    typealias Element = VideoPlayerDelegate
}

extension AVVideoPlayer: AVVideoAudioMixControlling {
    /// 返回当前 item 的配置；停止、失败和切换清理后自然返回 nil。
    var audioMix: AVAudioMix? { player.currentItem?.audioMix }

    /// 只修改已绑定 item；先校验 asset 身份，外部异步构建的旧 mix 不能污染其他资源。
    @discardableResult
    func update(audioMix: AVAudioMix?, for asset: AVURLAsset) -> Bool {
        guard let item = player.currentItem, item.asset === asset else { return false }
        item.audioMix = audioMix
        return true
    }
}

extension AVURLAsset: VideoPlayerURLAsset {
    
    public var value: URL {
        return url
    }
}

/// 一次寻时的生命周期；被覆盖、停止或系统取消时也只完成一次业务回调。
private class VideoPlayerSeekRequest {
    /// 调用方提交的目标和业务 completion。
    let target: VideoPlayer.Seek
    /// 是否已向 AVPlayer 提交，防止 ready 事件重复启动请求。
    var hasBegan = false
    /// completion 调用前置位，允许回调重入播放器而不重复完成。
    private var hasCompleted = false

    /// 保存请求上下文，供准备阶段延迟消费。
    init(_ target: VideoPlayer.Seek) {
        self.target = target
    }

    /// 必须在主线程调用；先标记完成，再执行可能重入的业务代码。
    func complete(_ finished: Bool) {
        guard !hasCompleted else { return }
        hasCompleted = true
        target.completion?(finished)
    }
}

/// 可选后台策略能力；不向 VideoPlayerable 增加要求，第三方后端不必实现无效的默认 setter。
public protocol VideoPlayerBackgroundControlling: VideoPlayerable {
    /// 默认 true 保留既有行为；false 时后台暂停、前台按用户意图恢复。PiP 与系统会话仍由宿主配置。
    var allowedBackgroundPlayback: Bool { get set }
}

extension AVVideoPlayer: VideoPlayerBackgroundControlling { }

/// 当前 AVPlayer item 的原生时钟快照；不使用 seek 目标或 current 的校准值。
public struct AVVideoNativePlaybackSample {
    /// 就绪且无待处理 seek 时的有效非负媒体秒；无资源、未就绪或 seek 中为 nil。
    public let position: TimeInterval?
    /// 包含准备期间尚未向 AVPlayer 提交的 seek 请求。
    public let seekPending: Bool
    /// AVPlayer 的瞬时执行速率；不同于 VideoPlayerable.rate 的目标速率。
    public let rate: Double
    /// 采样时的系统启动后秒数（单调时钟），不是日期或媒体时间。
    public let sampledAt: TimeInterval
}

/// AVPlayer 后端可选的只读监控能力；所有采样必须在主线程进行。
public protocol AVVideoNativePlaybackMonitoring: VideoPlayerable {
    /// item 时间和执行速率不证明扬声器或屏幕已经输出。
    var nativePlaybackSample: AVVideoNativePlaybackSample { get }
}

extension AVVideoPlayer: AVVideoNativePlaybackMonitoring {
    var nativePlaybackSample: AVVideoNativePlaybackSample {
        precondition(Thread.isMainThread)
        let pending = seekRequest != nil
        let seconds = player.currentItem?.currentTime().seconds
        let position: TimeInterval?
        if !pending, player.currentItem?.status == .readyToPlay,
           let seconds = seconds, seconds.isFinite, seconds >= 0 {
            position = seconds
        } else {
            position = nil
        }
        return .init(position: position, seekPending: pending, rate: Double(player.rate),
                     sampledAt: ProcessInfo.processInfo.systemUptime)
    }
}
