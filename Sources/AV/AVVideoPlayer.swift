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
import Foundation
import AVFoundation

public extension VideoPlayer {
    
    static let av: Builder = .init { AVVideoPlayer() }
}

class AVVideoPlayer: NSObject {
        
    static let shared = AVVideoPlayer()
    
    /// 当前URL
    var url: URL? {
        return currentUrl
    }
    
    /// 加载状态
    private(set) var loading: Bool = false {
        didSet {
            if loading {
                delegate { $0.videoPlayerLoadingBegin(self) }
            } else {
                delegate { $0.videoPlayerLoadingEnd(self) }
            }
        }
    }
    /// 播放状态
    private (set) var state: VideoPlayer.State = .stopped {
        didSet {
            switch state {
            case .playing:
                delegate { $0.videoPlayerPlaying(self) }
            case .paused:
                delegate { $0.videoPlayerPaused(self) }
            case .stopped:
                delegate { $0.videoPlayerStopped(self) }
            case .finish:
                delegate { $0.videoPlayerFinish(self) }
            case .error:
                delegate { $0.videoPlayerError(self) }
            }
        }
    }
    
    /// 播放速率 0.5 - 2.0
    var rate: Double = 1.0 {
        didSet { player.rate = Float(rate) }
    }
    /// 音量 0 - 1
    var volume: Double = 1.0 {
        didSet { player.volume = Float(volume)}
    }
    /// 是否静音
    var isMuted: Bool = false {
        didSet {
            player.isMuted = isMuted
        }
    }
    /// 是否循环播放
    var isLoop: Bool = false
    /// 是否后台播放
    var isBackground: Bool = false
    /// 是否自动播放
    var isAutoPlay: Bool = true
    /// 播放信息 (锁屏封面和远程控制)
    var playingInfo: VideoPlayerInfo? {
        didSet {
            guard let playingInfo = playingInfo else { return }
            
            playingInfo.set(self)
            add(delegate: playingInfo)
        }
    }
    
    var delegates: [DelegateBridge<AnyObject>] = []
    private lazy var player = AVPlayer()
    private lazy var playerLayer = AVPlayerLayer(player: player)
    private lazy var playerView: VideoPlayerView = VideoPlayerView()
    
    private var playerTimeObserver: Any?
    private var userPaused: Bool = false
    private var isSeeking: Bool = false
    private var ready: Bool = false
    private var currentUrl: URL?
    
    private var itemStatusObservation: NSKeyValueObservation?
    private var itemDurationObservation: NSKeyValueObservation?
    private var itemLoadedTimeRangesObservation: NSKeyValueObservation?
    private var itemPlaybackLikelyToKeepUpObservation: NSKeyValueObservation?
    
    override init() {
        super.init()
        
        setup()
        setupNotification()
    }
    
    private func setup() {
        rate = 1.0
        volume = 1.0
        isMuted = false
        isLoop = false
        isBackground = false
    }
    
    private func setupNotification() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(itemDidPlayToEndTime(_:)), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(itemPlaybackStalled(_:)), name: .AVPlayerItemPlaybackStalled, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruption(_:)), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
}

extension AVVideoPlayer {
    
    private func pauseNoUser() {
        player.pause()
        userPaused = false
        state = .paused
    }
}

extension AVVideoPlayer {
    
    /// 重置loading状态
    private func resetLoading() {
        guard loading else { return }
        
        loading = false
    }
    
    /// 错误
    private func error() {
        clear()
        resetLoading()
        state = .error
    }
    
    /// 清理
    private func clear() {
        guard let item = player.currentItem else { return }
        
        ready = false
        player.pause()
        
        // 移除监听
        removeObserver()
        removeObserver(item: item)
        
        // 移除item
        player.replaceCurrentItem(with: nil)
        playingInfo = nil
        currentUrl = nil
        
        VideoPlayer.removeAudioSession()
    }
    
    private func addObserver() {
        removeObserver()
        // 当前播放时间 (间隔: 每秒10次)
        let interval = CMTime(value: 1, timescale: 10)
        playerTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] (time) in
            guard let self = self else { return }
            
            let time = CMTimeGetSeconds(time)
            self.delegate{ $0.videoPlayer(self, updatedCurrent: time) }
        }
    }
    private func removeObserver() {
        guard let observer = playerTimeObserver else { return }
        playerTimeObserver = nil
        player.removeTimeObserver(observer)
    }
    
    private func addObserver(item: AVPlayerItem) {
        do {
            let observation = item.observe(\.status) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                
                switch observer.status {
                case .unknown: break
                case .readyToPlay:
                    if self.isAutoPlay {
                        self.player.play()
                        self.userPaused = false
                        self.state = .playing
                        
                    } else {
                        self.player.pause()
                        self.userPaused = true
                        self.state = .paused
                    }
                    self.ready = true
                    self.delegate { $0.videoPlayerReady(self) }
                    
                case .failed:
                    // 异常
                    print(item.error?.localizedDescription ?? "无法获取错误信息")
                    self.error()
                @unknown default:
                    break
                }
            }
            itemStatusObservation = observation
        }
        do {
            let observation = item.observe(\.duration) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                // 获取总时长
                let time = observer.duration.seconds
                self.delegate { $0.videoPlayer(self, updatedTotal: time) }
            }
            itemDurationObservation = observation
        }
        do {
            let observation = item.observe(\.loadedTimeRanges) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                guard let timeRange = observer.loadedTimeRanges.first as? CMTimeRange else { return }
                guard let totalTime = self.totalTime else { return }
                // 本次缓冲时间范围
                let start = timeRange.start.seconds
                let duration = timeRange.duration.seconds
                // 缓冲总时长
                let totalBuffer = start + duration
                // 缓冲进度
                let progress = totalBuffer / totalTime
                
                self.delegate { $0.videoPlayer(self, updatedBuffer: progress) }
            }
            itemLoadedTimeRangesObservation = observation
        }
        do {
            let observation = item.observe(\.isPlaybackLikelyToKeepUp) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                
                self.loading = !observer.isPlaybackLikelyToKeepUp
            }
            itemPlaybackLikelyToKeepUpObservation = observation
        }
    }
    private func removeObserver(item: AVPlayerItem) {
        itemStatusObservation?.invalidate()
        itemDurationObservation?.invalidate()
        itemLoadedTimeRangesObservation?.invalidate()
        itemPlaybackLikelyToKeepUpObservation?.invalidate()
    }
}

extension AVVideoPlayer {
    
    /// 播放结束通知
    @objc func itemDidPlayToEndTime(_ notification: NSNotification) {
        guard notification.object as? AVPlayerItem == player.currentItem else {
            return
        }
        
        seek(to: 0.0) { [weak self] in
            guard let self = self else { return }
            if self.isLoop {
                self.delegate { $0.videoPlayer(self, updatedCurrent: 0.0) }
            } else {
                self.player.pause()
                self.state = .finish
            }
        }
    }
    
    /// 播放异常通知
    @objc func itemPlaybackStalled(_ notification: NSNotification) {
        guard notification.object as? AVPlayerItem == player.currentItem else {
            return
        }
        if state == .playing { play() }
    }
    
    /// 会话线路变更通知
    @objc func sessionRouteChange(_ notification: NSNotification) {
        guard
            let info = notification.userInfo,
            let reason = info[AVAudioSessionRouteChangeReasonKey] as? Int else {
            return
        }
        guard let _ = player.currentItem else { return }
        
        switch AVAudioSession.RouteChangeReason(rawValue: UInt(reason)) {
        case .oldDeviceUnavailable?:
            DispatchQueue.main.async {
                self.pauseNoUser()
            }
        default: break
        }
    }
    
    /// 会话中断通知
    @objc func sessionInterruption(_ notification: NSNotification) {
        guard
            let info = notification.userInfo,
            let type = info[AVAudioSessionInterruptionTypeKey] as? Int else {
            return
        }
        guard let _ = player.currentItem else { return }
        
        switch AVAudioSession.InterruptionType(rawValue: UInt(type)) {
        case .began?:
            if !userPaused, state == .playing { pauseNoUser() }
        case .ended?:
            if !userPaused, state == .paused { play() }
        case .none:
            break
        @unknown default:
            break
        }
    }
    
    @objc func willEnterForeground(_ notification: NSNotification) {
        guard let _ = player.currentItem else { return }
        guard !isBackground else {
            // 恢复layer的播放器
            playerLayer.player = player
            return
        }
        if !userPaused, state == .paused { play() }
    }
    
    @objc func didEnterBackground(_ notification: NSNotification) {
        guard let _ = player.currentItem else { return }
        guard !isBackground else {
            // 后台播放模式时 移除layer的播放器 停止渲染 只播放音频
            playerLayer.player = nil
            return
        }
        if !userPaused, state == .playing { pauseNoUser() }
    }
}

extension AVVideoPlayer: VideoPlayerable {
    
    @discardableResult
    func prepare(url: URL) -> VideoPlayerView {
        
        clear()
        
        currentUrl = url
        let item = AVPlayerItem(url: url)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        player.rate = Float(rate)
        player.volume = Float(volume)
        player.isMuted = isMuted
        
        if #available(iOS 10.0, *) {
            player.automaticallyWaitsToMinimizeStalling = false
        }
        
        addObserver()
        addObserver(item: item)
        
        let layer = AVPlayerLayer(player: player)
        layer.masksToBounds = true
        self.playerLayer = layer
        
        loading = true
        state = .stopped
        
        // 构建播放视图
        playerView = VideoPlayerView({ (view) in
            view.layer.addSublayer(layer)
        })
        playerView.observe { (size, animation) in
            if let animation = animation {
                CATransaction.begin()
                CATransaction.setAnimationDuration(animation.duration)
                CATransaction.setAnimationTimingFunction(animation.timingFunction)
                layer.frame = .init(origin: .zero, size: size)
                CATransaction.commit()
                
            } else {
                layer.frame = .init(origin: .zero, size: size)
            }
        }
        playerView.observe { (contentMode) in
            switch contentMode {
            case .scaleToFill:
                layer.videoGravity = .resize
                
            case .scaleAspectFit:
                layer.videoGravity = .resizeAspect
                
            case .scaleAspectFill:
                layer.videoGravity = .resizeAspectFill
                
            default:
                layer.videoGravity = .resizeAspectFill
            }
        }
        playerView.contentMode = .scaleAspectFit
        
        // 设置音频会话
        VideoPlayer.setupAudioSession()
        
        return playerView
    }
    
    func play() {
        guard ready else { return }
        
        player.play()
        userPaused = false
        state = .playing
    }
    
    func pause() {
        guard ready else { return }
        
        player.pause()
        userPaused = true
        state = .paused
    }
    
    func stop() {
        clear()
        resetLoading()
        state = .stopped
    }
    
    func seek(to time: TimeInterval, completion: @escaping (() -> Void)) {
        guard ready else { return }
        guard
            let item = player.currentItem,
            player.status == .readyToPlay,
            !isSeeking else {
            completion()
            return
        }
        
        let state = self.state
        if state == .playing { player.pause() }
        
        // 暂时移除监听
        removeObserver()
        isSeeking = true
        
        let changeTime = CMTimeMakeWithSeconds(time, preferredTimescale: 1)
        item.seek(to: changeTime, completionHandler: { [weak self] (finish) in
            guard let self = self else { return }
            
            if state == .playing { self.player.play() }
            
            // 恢复监听
            self.addObserver()
            self.isSeeking = false
            self.delegate{ $0.videoPlayerSeekFinish(self) }
            completion()
        })
    }
    
    var currentTime: TimeInterval? {
        guard let item = player.currentItem else { return nil }
        let time = CMTimeGetSeconds(item.currentTime())
        return time.isNaN ? nil : time
    }
    
    var totalTime: TimeInterval? {
        guard let item = player.currentItem else { return nil }
        let time = CMTimeGetSeconds(item.duration)
        return time.isNaN ? nil : time
    }
    
    var view: VideoPlayerView {
        return playerView
    }
}

extension AVVideoPlayer: PlayerDelagetes  {
    
    typealias Element = VideoPlayerDelagete
}

