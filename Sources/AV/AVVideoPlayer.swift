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
    private(set) var url: URL?
    
    /// 播放状态
    private (set) var state: VideoPlayer.State = .stopped {
        didSet {
            delegate { $0.videoPlayerState(self, state: state) }
        }
    }
    
    /// 控制状态
    private(set) var control: VideoPlayer.ControlState = .pausing {
        didSet {
            delegate { $0.videoPlayerControlState(self, state: control) }
        }
    }
    
    /// 加载状态
    private(set) var loading: VideoPlayer.LoadingState = .ended {
        didSet {
            delegate { $0.videoPlayerLoadingState(self, state: loading) }
        }
    }
    
    /// 播放速率 0.5 - 2.0
    var rate: Double = 1.0 {
        didSet {
            guard case .playing = state else { return }
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
    /// 音频会话队列
    var audioSessionQueue: DispatchQueue = .audioSession
    
    var delegates: [VideoPlayerDelageteBridge<AnyObject>] = []
    private lazy var player = AVPlayer()
    private lazy var playerLayer = AVPlayerLayer(player: player)
    private lazy var playerView: VideoPlayerView = VideoPlayerView(.init())
    
    private var playerTimeObserver: Any?
    private var userPaused: Bool = false
    private var isSeeking: Bool = false
    
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
    
    /// 错误
    private func error(_ value: Swift.Error?) {
        clear(true)
        state = .failure(value)
    }
    
    /// 清理
    private func clear(_ isStop: Bool) {
        guard let item = player.currentItem else { return }
        
        loading = .ended
        
        player.pause()
        
        // 取消相关
        item.cancelPendingSeeks()
        item.asset.cancelLoading()
        
        // 移除监听
        removeObserver()
        removeObserver(item: item)
        
        // 移除item
        player.replaceCurrentItem(with: nil)
        // 清空当前URL
        url = nil
        // 设置Seek状态
        isSeeking = false
        
        // 移除音频会话
        if isStop { VideoPlayer.removeAudioSession(in: audioSessionQueue) }
    }
    
    private func addObserver() {
        removeObserver()
        // 当前播放时间 (间隔: 每秒10次)
        let interval = CMTime(value: 1, timescale: 10)
        playerTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] (time) in
            guard let self = self else { return }
            guard !self.isSeeking else { return }
            
            self.delegate{ $0.videoPlayer(self, updatedCurrent: CMTimeGetSeconds(time)) }
        }
        
        timeControlStatusObservation = player.observe(\.timeControlStatus) {
            [weak self] (observer, change) in
            guard let self = self else { return }
            guard case .playing = self.state else { return }
            
            switch observer.timeControlStatus {
            case .paused:
                self.control = .pausing
                self.userPaused = false
                
            case .playing:
                // 校准播放速率
                if observer.rate == .init(self.rate) {
                    self.control = .playing
                    self.userPaused = false
                    
                } else {
                    observer.rate = .init(self.rate)
                }
                
            default:
                break
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
                self.loading = .began
                
            case .evaluatingBufferingRate?:
                print("evaluatingBufferingRate")
                
            case .noItemToPlay?:
                print("noItemToPlay")
                
            default:
                self.loading = .ended
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
                    self.state = .playing
                    self.itemStatusObservation = nil
                    
                    if self.isAutoPlay {
                        self.play()
                        
                    } else {
                        self.pause()
                    }
                    
                case .failed:
                    self.error(item.error)
                    
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
                
                self.delegate { $0.videoPlayer(self, updatedDuration: observer.duration.seconds) }
            }
            itemDurationObservation = observation
        }
        do {
            let observation = item.observe(\.loadedTimeRanges) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                
                self.delegate { $0.videoPlayer(self, updatedBuffer: self.buffer) }
            }
            itemLoadedTimeRangesObservation = observation
        }
        do {
            let observation = item.observe(\.isPlaybackLikelyToKeepUp) {
                [weak self] (observer, change) in
                guard let self = self else { return }
                
                self.loading = !observer.isPlaybackLikelyToKeepUp ? .began : .ended
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
        guard let item = notification.object as? AVPlayerItem, item == player.currentItem else {
            return
        }
        // 取消Seeks
        item.cancelPendingSeeks()
        // 设置Seek状态
        isSeeking = true
        // Seek到起始位置
        item.seek(to: .zero) { [weak self] (result) in
            guard let self = self else { return }
            // 设置Seek状态
            self.isSeeking = false
            // 判断循环模式
            if self.isLoop {
                // 继续播放
                self.player.playImmediately(atRate: .init(self.rate))
                
            } else {
                // 暂停播放
                self.player.pause()
                self.userPaused = true
                // 设置完成状态
                self.state = .finished
            }
        }
    }
    
    /// 播放异常通知
    @objc
    private func itemPlaybackStalled(_ notification: NSNotification) {
        guard notification.object as? AVPlayerItem == player.currentItem else {
            return
        }
        guard case .playing = state else {
            return
        }
        play()
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
            if !userPaused, control == .playing { player.pause() }
        case .ended?:
            if !userPaused, control == .pausing { play() }
        default:
            break
        }
    }
    
    @objc
    private func willEnterForeground(_ notification: NSNotification) {
        guard let item = player.currentItem else { return }
        guard !userPaused, control == .pausing else { return }
        
        var observation: NSKeyValueObservation?
        observation = item.observe(\.status) { [weak self] (observer, change) in
            observation = nil
            guard let self = self else { return }
            
            switch observer.status {
            case .readyToPlay:
                self.play()
                
            case .failed:
                self.error(item.error)
                
            default:
                break
            }
        }
    }
}

extension AVVideoPlayer: VideoPlayerable {
    
    @discardableResult
    func prepare(url: URL) -> VideoPlayerView {
        // 清理原有资源
        clear(false)
        // 重置当前状态
        loading = .began
        state = .prepare
        
        // 设置当前URL
        self.url = url
        // 初始化播放器
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
        
        // 添加监听
        addObserver()
        addObserver(item: item)
        
        let layer = AVPlayerLayer(player: player)
        layer.masksToBounds = true
        self.playerLayer = layer
        
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
        switch state {
        case .playing where !isSeeking:
            player.playImmediately(atRate: .init(rate))
            
        case .finished:
            state = .playing
            player.playImmediately(atRate: .init(rate))
            
        default:
            break
        }
    }
    
    func pause() {
        guard case .playing = state, !isSeeking else { return }
        
        player.pause()
        userPaused = true
    }
    
    func stop() {
        clear(true)
        state = .stopped
    }
    
    func seek(to time: TimeInterval, completion: @escaping (() -> Void)) {
        guard
            !isSeeking,
            let item = player.currentItem,
            let range = item.seekableTimeRanges.first?.timeRangeValue,
            player.status == .readyToPlay,
            case .playing = state else {
            return
        }
        
        // 记录当前状态
        let player = self.player
        let isPlaying = control == .playing
        if isPlaying {
            player.pause()
        }
        
        // 设置Seek状态
        isSeeking = true
        
        // 限制可跳转时间范围
        let changeTime = CMTimeMakeWithSeconds(
            min(max(time, range.start.seconds), range.duration.seconds),
            preferredTimescale: range.duration.timescale
        )
        item.seek(to: changeTime) { [weak self] (finished) in
            guard let self = self else { return }
            guard finished else { return }
            // 设置Seek状态
            self.isSeeking = false
            // 恢复播放
            if isPlaying {
                player.playImmediately(atRate: .init(self.rate))
            }
            
            self.delegate { $0.videoPlayerSeekFinish(self) }
            completion()
        }
    }
    
    var current: TimeInterval {
        guard let item = player.currentItem else { return 0 }
        let time = CMTimeGetSeconds(item.currentTime())
        return time.isNaN ? 0 : time
    }
    
    var duration: TimeInterval {
        guard let item = player.currentItem else { return 0 }
        let time = CMTimeGetSeconds(item.duration)
        return time.isNaN ? 0 : time
    }
    
    var buffer: Double {
        guard let item = player.currentItem else { return 0 }
        guard let range = item.loadedTimeRanges.first?.timeRangeValue else { return 0 }
        guard duration > 0 else { return 0 }
        let buffer = range.start.seconds + range.duration.seconds
        return buffer / duration
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
