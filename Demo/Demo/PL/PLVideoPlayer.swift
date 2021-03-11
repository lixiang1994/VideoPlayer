//
//  PLVideoPlayer.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//
import UIKit
import VideoPlayer

#if !targetEnvironment(simulator)

import PLPlayerKit

extension VideoPlayer {
    
    static let pl: Builder = .init { PLVideoPlayer() }
}

class PLVideoPlayer: NSObject {
    
    static let shared = PLVideoPlayer()
    
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
    
    private(set) var buffer: Double = 0
    
    /// 播放速率 0.5 - 2.0
    var rate: Double = 1.0 {
        didSet { player?.playSpeed = rate }
    }
    /// 音量 0 - 1
    var volume: Double = 1.0 {
        didSet { player?.setVolume(.init(volume)) }
    }
    /// 是否静音
    var isMuted: Bool = false {
        didSet {
            player?.isMute = isMuted
        }
    }
    /// 是否循环播放
    var isLoop: Bool = false {
        didSet {
            player?.loopPlay = isLoop
        }
    }
    /// 是否自动播放
    var isAutoPlay: Bool = true
    /// 音频会话队列
    var audioSessionQueue: DispatchQueue = .audioSession
    
    var delegates: [VideoPlayerDelegateBridge<AnyObject>] = []
    private var playTimer: Timer?
    private var player: PLPlayer?
    private var playerView = VideoPlayerView(.init())
    private var userPaused: Bool = false
    private var seekCompletion: (() -> Void)?
    
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
        
        let timer = Timer(
            timeInterval: 0.1,
            target: WeakObject(self),
            selector: #selector(timerAction),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        timer.fireDate = .distantFuture
        playTimer = timer
    }
    
    private func setupNotification() {
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
    }
    
    private func pauseNoUser() {
        player?.pause()
        userPaused = false
    }
    
    deinit {
        playTimer?.invalidate()
        playTimer = nil
    }
}

extension PLVideoPlayer {
    
    @objc func timerAction() {
        delegate { $0.videoPlayer(self, updatedCurrent: current) }
        delegate { $0.videoPlayer(self, updatedDuration: duration) }
    }
    
    /// 会话线路变更通知
    @objc func sessionRouteChange(_ notification: NSNotification) {
        guard
            let info = notification.userInfo,
            let reason = info[AVAudioSessionRouteChangeReasonKey] as? Int else {
            return
        }
        guard let _ = player else { return }
        
        switch AVAudioSession.RouteChangeReason(rawValue: .init(reason)) {
        case .oldDeviceUnavailable?:
            DispatchQueue.main.async { [weak self] in
                self?.pauseNoUser()
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
        guard let _ = player else { return }
        
        switch AVAudioSession.InterruptionType(rawValue: .init(type)) {
        case .began?:
            if !userPaused, control == .playing { pauseNoUser() }
        case .ended?:
            if !userPaused, control == .pausing { play() }
        default:
            break
        }
    }
}

extension PLVideoPlayer {
    
    /// 清理
    private func clear(_ isStop: Bool) {
        player?.stop()
        // 重置缓冲进度
        buffer = 0
        // 重置加载状态
        loading = .ended
        
        if isStop { VideoPlayer.removeAudioSession(in: audioSessionQueue) }
    }
    
    /// 错误
    private func error(_ value: Swift.Error?) {
        clear(true)
        state = .failure(value)
    }
}

extension PLVideoPlayer: PLPlayerDelegate {
    /*
     PLPlayerStatusUnknow    初始化时指定的状态，不会有任何状态会跳转到这一状态
     PLPlayerStatusPreparing    播放器正在准备当中
     PLPlayerStatusReady    播放器准备完成的状态
     PLPlayerStatusOpen    播放器准备开始连接的状态
     PLPlayerStatusCaching    播放器正在缓存的状态
     PLPlayerStatusPlaying    播放器正在播放的状态
     PLPlayerStatusPaused    播放器暂停的状态
     PLPlayerStatusStopped    播放器播放结束或手动停止的状态
     PLPlayerStatusError    播放器出现错误的状态
     PLPlayerStateAutoReconnecting    播放器开始自动重连
     PLPlayerStatusCompleted    点播播放完成
     */
    func player(_ player: PLPlayer, statusDidChange state: PLPlayerStatus) {
        switch state {
        case .statusPreparing:
            // 播放器正在准备当中
            print("播放器正在准备当中")
            loading = .began
            
        case .statusCaching:
            // 播放器正在缓存的状态
            print("缓存状态")
            loading = .began
            
        case .statusReady:
            print("准备完成")
            loading = .ended
            
        case .statusOpen:
            print("开始连接")
            loading = .ended
           
        case .statusPlaying:
            // 播放器正在播放的状态
            print("开始播放")
            loading = .ended
            
            if case .prepare = self.state {
                if isAutoPlay {
                    playTimer?.fireDate = .init()
                    userPaused = false
                    control = .playing
                    player.play()
                    
                } else {
                    control = .pausing
                    userPaused = true
                    player.pause()
                }
                self.state = .playing
            }
            
        case .statusPaused:
            // 播放器暂停的状态
            print("暂停播放")
            control = .pausing
            
        case .statusError:
            // 播放器错误的状态
            print("播放错误")
            player.play()
            
        case .stateAutoReconnecting:
            // 播放器开始自动重连
            loading = .began
            
        case .statusCompleted:
            loading = .ended
            self.state = .finished
            
        default: break
        }
    }
    
    func player(_ player: PLPlayer, stoppedWithError error: Error?) {
        self.error(error)
    }
    
    func player(_ player: PLPlayer, loadedTimeRange timeRange: CMTime) {
        guard duration > 0 else { return }
        // 缓冲进度
        let progress = timeRange.seconds / duration
        
        print(
            """
            ==========pl===========
            duration \(duration)\n
            progress \(progress)\n
            """
        )
        buffer = progress
        delegate { $0.videoPlayer(self, updatedBuffer: progress) }
    }
    
    func player(_ player: PLPlayer, seekToCompleted isCompleted: Bool) {
        loading = .ended
        // 恢复监听
        delegate { $0.videoPlayerSeekFinish(self) }
        seekCompletion?()
        seekCompletion = nil
    }
    
    func playerWillBeginBackgroundTask(_ player: PLPlayer) {
        guard let _ = player.playerView else { return }
        
        playTimer?.fireDate = .distantFuture
        if !userPaused, control == .playing { pauseNoUser() }
    }
    
    func playerWillEndBackgroundTask(_ player: PLPlayer) {
        guard let _ = player.playerView else { return }
        
        playTimer?.fireDate = .init()
        if !userPaused, control == .pausing { play() }
    }
}

extension PLVideoPlayer: VideoPlayerDelegates {
    
    typealias Element = VideoPlayerDelegate
}

extension PLVideoPlayer: VideoPlayerable {
    
    @discardableResult
    func prepare(url: URL) -> VideoPlayerView {
        // 清理原有资源
        clear(false)
        // 重置当前状态
        loading = .began
        state = .prepare
        
        guard
            let player = PLPlayer(url: url, option: PLPlayerOption.default()),
            let view = player.playerView else {
            state = .failure(.none)
            return VideoPlayerView(.init())
        }
        
        player.delegate = self
        player.isBackgroundPlayEnable = false
        player.loopPlay = isLoop
        player.playSpeed = rate
        player.setVolume(.init(volume))
        player.isMute = isMuted
        self.player = player
        
        playerView = VideoPlayerView(view.layer)
        playerView.observe { (contentMode) in
            view.contentMode = contentMode
        }
        playerView.observe { (size, animation) in
            view.frame = .init(origin: .zero, size: size)
        }
        playerView.backgroundColor = .clear
        playerView.contentMode = .scaleAspectFit
        
        playTimer?.fireDate = .init()
        
        // 设置音频会话
        VideoPlayer.setupAudioSession(in: audioSessionQueue)
        
        player.play()
        
        return playerView
    }
    
    func play() {
        guard case .playing = state else { return }
        
        playTimer?.fireDate = .init()
        control = .playing
        userPaused = false
        player?.resume()
    }
    
    func pause() {
        guard case .playing = state else { return }
        
        control = .pausing
        userPaused = true
        player?.pause()
    }
    
    func stop() {
        clear(true)
        loading = .ended
        playTimer?.fireDate = .distantFuture
        state = .stopped
    }
    
    func seek(to time: TimeInterval, completion: @escaping (() -> Void)) {
        guard case .playing = state else { return }
        guard
            let player = player,
            player.status == .statusCaching ||
            player.status == .statusPlaying ||
            player.status == .statusPaused else {
            completion()
            return
        }
        guard seekCompletion == nil else {
            completion()
            return
        }
        
        loading = .began
        player.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: 1000))
        seekCompletion = completion
    }
    
    var current: TimeInterval {
        guard let duration = player?.currentTime else { return 0 }
        
        let time = duration.seconds
        return time.isNaN ? 0 : time
    }
    
    var duration: TimeInterval {
        guard let duration = player?.totalDuration else { return 0 }
        
        let time = duration.seconds
        return time.isNaN ? 0 : time
    }
    
    var view: VideoPlayerView {
        return playerView
    }
    
    func screenshot(completion: @escaping (UIImage?) -> Void) {
        guard let player = player else {
            completion(.none)
            return
        }
        player.getScreenShot(completionHandler: { (image) in
            completion(image)
        })
    }
}

#endif
