import VideoPlayer

class VideoPlayerProvider: NSObject {
    
    typealias ControlView = UIView & VideoPlayerControlViewable
    typealias FinishView = UIView & VideoPlayerFinishViewable
    typealias ErrorView = UIView & VideoPlayerErrorViewable
    typealias CoverView = UIView & VideoPlayerCoverViewable
    
    private weak var player: VideoPlayerable?
    
    private let controlView: ControlView?
    private let finishView: FinishView?
    private let errorView: ErrorView?
    private let coverView: CoverView?
    private let playHandle: (() -> Void)
    
    init(control: ControlView?,
         finish: FinishView?,
         error: ErrorView?,
         cover: CoverView?,
         playHandle handle: @escaping (() -> Void)) {
        
        controlView = control
        finishView = finish
        errorView = error
        coverView = cover
        playHandle = handle
        super.init()
        
        controlView?.isHidden = true
        controlView?.set(delegate: self)
        
        finishView?.isHidden = true
        finishView?.set(delegate: self)
        
        errorView?.isHidden = true
        errorView?.set(delegate: self)
        
        coverView?.isHidden = true
        coverView?.set(delegate: self)
    }
    
    deinit { print("deinit:\t\(classForCoder)") }
}

extension VideoPlayerProvider {
    
    /// 设置播放器
    ///
    /// - Parameter player: 播放器
    func set(player: VideoPlayerable?) {
        defer {
            self.player?.remove(delegate: self)
            self.player = player
            player?.add(delegate: self)
        }
        guard let player = player else {
            return
        }
        
        switch player.state {
        case .playing:  videoPlayerPlaying(player)
        case .paused:   videoPlayerPaused(player)
        case .stopped:  videoPlayerStopped(player)
        case .finish:   videoPlayerFinish(player)
        case .error:    videoPlayerError(player)
        }
    }
}

extension VideoPlayerProvider: VideoPlayerDelagete {
    
    func videoPlayerLoadingBegin(_ player: VideoPlayerable) {
        controlView?.loadingBegin()
    }
    func videoPlayerLoadingEnd(_ player: VideoPlayerable) {
        controlView?.loadingEnd()
    }
    
    func videoPlayerReady(_ player: VideoPlayerable) {
        controlView?.set(enabled: true)
    }
    
    func videoPlayerPlaying(_ player: VideoPlayerable) {
        controlView?.set(state: true)
        controlView?.isHidden = false
        finishView?.isHidden = true
        errorView?.isHidden = true
        coverView?.isHidden = true
    }
    
    func videoPlayerPaused(_ player: VideoPlayerable) {
        controlView?.set(state: false)
        controlView?.isHidden = false
        finishView?.isHidden = true
        errorView?.isHidden = true
        coverView?.isHidden = true
    }
    
    func videoPlayerStopped(_ player: VideoPlayerable) {
        controlView?.set(enabled: false)
        controlView?.isHidden = true
        finishView?.isHidden = true
        errorView?.isHidden = true
        coverView?.isHidden = false
    }
    
    func videoPlayerFinish(_ player: VideoPlayerable) {
        controlView?.isHidden = true
        finishView?.isHidden = false
        errorView?.isHidden = true
        coverView?.isHidden = true
    }
    
    func videoPlayerError(_ player: VideoPlayerable) {
        controlView?.set(enabled: false)
        controlView?.isHidden = true
        finishView?.isHidden = true
        errorView?.isHidden = false
        coverView?.isHidden = true
    }
    
    func videoPlayer(_ player: VideoPlayerable, updatedBuffer progress: Double) {
        controlView?.set(buffer: progress, animated: true)
    }
    
    func videoPlayer(_ player: VideoPlayerable, updatedTotal time: Double) {
        controlView?.set(total: time)
    }
    
    func videoPlayer(_ player: VideoPlayerable, updatedCurrent time: Double) {
        controlView?.set(current: time)
    }
    
    func videoPlayerSeekFinish(_ player: VideoPlayerable) {
        
    }
}

extension VideoPlayerProvider: VideoPlayerControlViewDelegate {
    
    func controlPlay() {
        player?.play()
    }
    
    func controlPause() {
        player?.pause()
    }
    
    func controlSeek(time: Double, completion: @escaping (()->Void)) {
        player?.seek(to: time, completion: completion)
    }
}

extension VideoPlayerProvider: VideoPlayerFinishViewDelegate {
    
    func finishReplay() {
        player?.play()
    }
}

extension VideoPlayerProvider: VideoPlayerErrorViewDelegate {
    
    func errorRetry() {
        playHandle()
    }
}

extension VideoPlayerProvider: VideoPlayerCoverViewDelegate {
    
    func play() {
        playHandle()
        coverView?.isHidden = true
    }
}
