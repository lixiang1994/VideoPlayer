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
        didSet {
            guard state == .playing else { return }
            player.rate = .init(rate)
        }
    }
    /// 音量 0 - 1
    var volume: Double = 1.0 {
        didSet { player.volume = .init(volume)}
    }
    /// 是否静音
    var isMuted: Bool = false {
        didSet {
            player.isMuted = isMuted
        }
    }
    /// 是否循环播放
    var isLoop: Bool = false
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
    /// 音频会话队列
    var audioSessionQueue: DispatchQueue = .audioSession
    
    var delegates: [VideoPlayerDelageteBridge<AnyObject>] = []
    private lazy var player = AVPlayer()
    private lazy var playerLayer = AVPlayerLayer(player: player)
    private lazy var playerView: VideoPlayerView = VideoPlayerView(.init())
    
    private var playerTimeObserver: Any?
    private var userPaused: Bool = false
    private var isSeeking: Bool = false
    private var ready: Bool = false
    private var currentUrl: URL?
    
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var reasonForWaitingToPlayObservation: NSKeyValueObservation?
    
    private var itemStatusObservation: NSKeyValueObservation?
    private var itemDurationObservation: NSKeyValueObservation?
    private var itemLoadedTimeRangesObservation: NSKeyValueObservation?
    private var itemPlaybackLikelyToKeepUpObservation: NSKeyValueObservation?
    
    /// 后台任务标识
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    
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
    }
    
    private func setupNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEndTime),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemPlaybackStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
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
        clear(true)
        resetLoading()
        state = .error
    }
    
    /// 清理
    private func clear(_ isStop: Bool) {
        guard let item = player.currentItem else { return }
        
        ready = false
        player.pause()
        
        // 取消相关
        item.cancelPendingSeeks()
        item.asset.cancelLoading()
        
        // 移除监听
        removeObserver()
        removeObserver(item: item)
        
        // 移除item
        player.replaceCurrentItem(with: nil)
        playingInfo = nil
        currentUrl = nil
        
        if isStop { VideoPlayer.removeAudioSession(in: audioSessionQueue) }
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
        
        timeControlStatusObservation = player.observe(\.timeControlStatus) {
            [weak self] (observer, change) in
            guard let self = self else { return }
            
            switch observer.timeControlStatus {
            case .paused:
                self.state = .paused
                self.userPaused = false
                
            case .playing:
                self.state = .playing
                self.userPaused = false
                
            case .waitingToPlayAtSpecifiedRate:
                print("waitingToPlayAtSpecifiedRate")
            }
        }
        
        reasonForWaitingToPlayObservation = player.observe(\.reasonForWaitingToPlay) {
            [weak self] (observer, change) in
            guard let self = self else { return }
            guard observer.automaticallyWaitsToMinimizeStalling else { return }
            guard observer.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
            
            switch observer.reasonForWaitingToPlay {
            case .toMinimizeStalls?:
                print("toMinimizeStalls")
                self.loading = true
                
            case .evaluatingBufferingRate?:
                print("evaluatingBufferingRate")
                
            case .noItemToPlay?:
                print("noItemToPlay")
                
            default:
                self.loading = false
            }
        }
    }
    private func removeObserver() {
        if let observer = playerTimeObserver {
            playerTimeObserver = nil
            player.removeTimeObserver(observer)
        }
        
        if let observer = timeControlStatusObservation {
            observer.invalidate()
            timeControlStatusObservation = nil
        }
        
        if let observer = reasonForWaitingToPlayObservation {
            observer.invalidate()
            reasonForWaitingToPlayObservation = nil
        }
    }
    
    private func addObserver(item: AVPlayerItem) {
        do {
            let observation = item.observe(\.status) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                
                switch observer.status {
                case .readyToPlay:
                    if self.isAutoPlay {
                        self.player.playImmediately(atRate: .init(self.rate))
                        
                    } else {
                        self.player.pause()
                        self.userPaused = true
                    }
                    self.ready = true
                    self.delegate { $0.videoPlayerReady(self) }
                    self.itemStatusObservation = nil
                    
                case .failed:
                    // 异常
                    print(item.error?.localizedDescription ?? "无法获取错误信息")
                    self.error()
                    
                default:
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
                self.itemDurationObservation = nil
            }
            itemDurationObservation = observation
        }
        do {
            let observation = item.observe(\.loadedTimeRanges) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                guard let timeRange = observer.loadedTimeRanges.first?.timeRangeValue else { return }
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
        itemStatusObservation = nil
        itemDurationObservation = nil
        itemLoadedTimeRangesObservation = nil
        itemPlaybackLikelyToKeepUpObservation = nil
    }
}

extension AVVideoPlayer {
    
    /// 播放结束通知
    @objc
    private func itemDidPlayToEndTime(_ notification: NSNotification) {
        guard notification.object as? AVPlayerItem == player.currentItem else {
            return
        }
        
        seek(to: 0.0) { [weak self] in
            guard let self = self else { return }
            if self.isLoop {
                self.delegate { $0.videoPlayer(self, updatedCurrent: 0.0) }
                
            } else {
                self.player.pause()
                self.userPaused = true
                self.state = .finish
            }
        }
    }
    
    /// 播放异常通知
    @objc
    private func itemPlaybackStalled(_ notification: NSNotification) {
        guard notification.object as? AVPlayerItem == player.currentItem else {
            return
        }
        if state == .playing { play() }
    }
    
    /// 会话线路变更通知
    @objc
    private func sessionRouteChange(_ notification: NSNotification) {
        guard
            let info = notification.userInfo,
            let reason = info[AVAudioSessionRouteChangeReasonKey] as? Int else {
            return
        }
        guard let _ = player.currentItem else { return }
        
        switch AVAudioSession.RouteChangeReason(rawValue: UInt(reason)) {
        case .oldDeviceUnavailable?:
            DispatchQueue.main.async {
                self.player.pause()
            }
        default: break
        }
    }
    
    /// 会话中断通知
    @objc
    private func sessionInterruption(_ notification: NSNotification) {
        guard
            let info = notification.userInfo,
            let type = info[AVAudioSessionInterruptionTypeKey] as? Int else {
            return
        }
        guard let _ = player.currentItem else { return }
        
        switch AVAudioSession.InterruptionType(rawValue: .init(type)) {
        case .began?:
            if !userPaused, state == .playing { player.pause() }
        case .ended?:
            if !userPaused, state == .paused { play() }
        case .none:
            break
        @unknown default:
            break
        }
    }
    
    @objc
    private func willEnterForeground(_ notification: NSNotification) {
        guard let item = player.currentItem else { return }
        guard !userPaused, state == .paused else { return }
        var observation: NSKeyValueObservation?
        observation = item.observe(\.status) {
            [weak self] (observer, change) in
            defer { observation = nil }
            guard let self = self else { return }
            
            switch observer.status {
            case .readyToPlay:
                self.play()
                
            case .failed:
                self.error()
                
            default:
                break
            }
        }
    }
}

extension AVVideoPlayer: VideoPlayerable {
    
    @discardableResult
    func prepare(url: URL) -> VideoPlayerView {
        
        clear(false)
        
        currentUrl = url
        let item = AVPlayerItem(url: url)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        // 预缓冲时长 默认60秒
        item.preferredForwardBufferDuration = 60.0
        // 解决0.5倍数播放回音问题
        item.audioTimePitchAlgorithm = .timeDomain
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        player.rate = .init(rate)
        player.volume = .init(volume)
        player.isMuted = isMuted
        
        player.automaticallyWaitsToMinimizeStalling = false
        
        addObserver()
        addObserver(item: item)
        
        let layer = AVPlayerLayer(player: player)
        layer.masksToBounds = true
        self.playerLayer = layer
        
        loading = true
        state = .stopped
        
        // 构建播放视图
        playerView = VideoPlayerView(layer)
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
        VideoPlayer.setupAudioSession(in: audioSessionQueue)
        
        return playerView
    }
    
    func play() {
        guard ready else { return }
        guard !isSeeking else { return }
        
        player.playImmediately(atRate: .init(rate))
    }
    
    func pause() {
        guard ready else { return }
        guard !isSeeking else { return }
        
        player.pause()
        userPaused = true
    }
    
    func stop() {
        clear(true)
        resetLoading()
        state = .stopped
    }
    
    func seek(to time: TimeInterval, completion: @escaping (() -> Void)) {
        guard
            ready,
            let item = player.currentItem,
            player.status == .readyToPlay,
            !isSeeking else {
            return
        }
        
        let player = self.player
        let isPlaying = state == .playing
        if isPlaying { player.pause() }
        
        isSeeking = true
        
        let changeTime = CMTimeMakeWithSeconds(time, preferredTimescale: 1)
        item.seek(to: changeTime) { [weak self] (finished) in
            guard let self = self else { return }
            guard finished, player == self.player else { return }
            
            if isPlaying {
                player.playImmediately(atRate: .init(self.rate))
            }
            
            self.isSeeking = false
            self.delegate { $0.videoPlayerSeekFinish(self) }
            completion()
        }
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

extension AVVideoPlayer: VideoPlayerDelagetes {
    
    typealias Element = VideoPlayerDelagete
}

fileprivate extension AVPlayerItem {
    
    func setAudioTrack(_ isEnabled: Bool) {
        tracks.filter { $0.assetTrack?.mediaType == .some(.audio) }.forEach { $0.isEnabled = isEnabled }
    }
}
