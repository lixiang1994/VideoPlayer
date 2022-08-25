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
    
    static let pl: Builder = .init { PLVideoPlayer($0) }
}

class PLVideoPlayer: NSObject {
    
    /// 当前URL
    private(set) var resource: VideoPlayerURLAsset?
    
    /// 配置
    private(set) var configuration: VideoPlayerConfiguration
    
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
    
    var delegates: [VideoPlayerDelegateBridge<AnyObject>] = []
    
    private var playTimer: Timer?
    private var player: PLPlayer?
    private var playerView = VideoPlayerView(.init())
    
    /// 当前时间校准器 用于解决时间精度偏差问题.
    private var currentTimeCalibrator: TimeInterval?
    /// 跳转意图 例如当非playing状态时 如果调用了seek(to:)  记录状态 在playing时设置跳转
    private var intendedToSeek: VideoPlayer.Seek?
    /// 播放意图 例如当seeking时如果调用了play() 或者 pasue() 记录状态 在seeking结束时设置对应状态
    private var intendedToPlay: Bool = false
    
    init(_ configuration: VideoPlayerConfiguration) {
        self.configuration = configuration
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
    @objc
    private func sessionInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let type = info[AVAudioSessionInterruptionTypeKey] as? Int else {
            return
        }
        
        switch AVAudioSession.InterruptionType(rawValue: .init(type)) {
        case .began? where intendedToPlay:
            pauseNoUser()
            
        case .ended? where intendedToPlay:
            play()
            
        default:
            break
        }
    }
}

extension PLVideoPlayer {
    
    /// 清理
    private func clear() {
        player?.stop()
        playTimer?.fireDate = .distantFuture
        // 重置缓冲进度
        buffer = 0
        // 重置加载状态
        loading = .ended
        // 清空资源
        resource = nil
        // 清理意图
        intendedToSeek = nil
        intendedToPlay = false
    }
    
    /// 错误
    private func error(_ value: Swift.Error?) {
        clear()
        state = .failed(value)
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
                // 查看是否有需要的Seek
                if let seek = self.intendedToSeek {
                    player.pause()
                    self.seek(to: seek)
                    
                } else {
                    self.state = .playing
                    
                    if self.intendedToPlay {
                        self.play()
                        
                    } else {
                        self.pause()
                    }
                }
            }
            
        case .statusPaused:
            // 播放器暂停的状态
            print("暂停播放")
            control = .pausing
            
        case .statusError:
            // 播放器错误的状态
            print("播放错误")
            error(nil)
            
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
        guard let target = intendedToSeek else {
            return
        }
        // 停止加载
        loading = .ended
        // 清空跳转意图
        intendedToSeek = nil
        // 设置当前时间校准器
        currentTimeCalibrator = target.time
        // 根据播放意图继续播放
        if isCompleted, intendedToPlay {
            play()
        }
        // 代理回调 结束跳转
        delegate { $0.videoPlayer(self, seekEnded: target) }
        
        // 如果是准备阶段 则切换到播放状态
        if case .prepare = self.state {
            self.state = .playing
            
            if self.intendedToPlay {
                self.play()
                
            } else {
                self.pause()
            }
        }
    }
    
    func playerWillBeginBackgroundTask(_ player: PLPlayer) {
        guard let _ = player.playerView else { return }
        
        playTimer?.fireDate = .distantFuture
        if case .playing = state, intendedToPlay { pauseNoUser() }
    }
    
    func playerWillEndBackgroundTask(_ player: PLPlayer) {
        guard let _ = player.playerView else { return }
        
        playTimer?.fireDate = .init()
        if case .playing = state, intendedToPlay { play() }
    }
}

extension PLVideoPlayer: VideoPlayerDelegates {
    
    typealias Element = VideoPlayerDelegate
}

extension PLVideoPlayer: VideoPlayerable {
    
    @discardableResult
    func prepare(resource: VideoPlayerURLAsset) -> VideoPlayerView {
        // 清理原有资源
        clear()
        // 重置当前状态
        loading = .began
        state = .prepare
        
        guard
            let player = PLPlayer(url: resource.value, option: PLPlayerOption.default()),
            let view = player.playerView else {
            state = .failed(.none)
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
        
        player.play()
        
        // 设置初始播放意图
        intendedToPlay = configuration.isAutoplay
        
        return playerView
    }
    
    func play() {
        switch state {
        case .prepare:
            intendedToPlay = true
            
        case .playing where intendedToSeek != nil:
            intendedToPlay = true
            
        case .playing where intendedToSeek == nil:
            intendedToPlay = true
            player?.resume()
            control = .playing
            playTimer?.fireDate = .init()
            
        case .finished:
            state = .playing
            intendedToPlay = true
            // Seek到起始位置
            seek(to: .init(time: .zero))
            
        default:
            break
        }
    }
    
    func pause() {
        intendedToPlay = false
        control = .pausing
        player?.pause()
    }
    
    func stop() {
        clear()
        state = .stopped
    }
    
    func seek(to target: VideoPlayer.Seek) {
        guard
            let player = player,
            player.status == .statusCaching ||
            player.status == .statusPlaying ||
            player.status == .statusPaused,
            case .playing = state else {
            // 设置跳转意图
            intendedToSeek = target
            return
        }
        // 设置跳转意图
        intendedToSeek = target
        // 暂停当前播放
        player.pause()
        // 开始加载中
        loading = .began
        // 代理回调 当前时间为目标时间
        delegate { $0.videoPlayer(self, updatedCurrent: target.time) }
        // 代理回调 开始跳转
        delegate { $0.videoPlayer(self, seekBegan: target) }
        // 开始Seek
        player.seek(to: CMTimeMakeWithSeconds(target.time, preferredTimescale: 1000))
    }
    
    var current: TimeInterval {
        guard let duration = player?.currentTime else { return 0 }
        let time = duration.seconds
        // 如果有跳转意图 则返回跳转的目标时间
        if let seek = intendedToSeek {
            return seek.time
        }
        // 当前时间校准器 如果大于 当前时间, 则返回校准时间, 否则清空校准器 返回当前时间.
        if let temp = currentTimeCalibrator, temp > time {
            return temp
        }
        currentTimeCalibrator = nil
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
