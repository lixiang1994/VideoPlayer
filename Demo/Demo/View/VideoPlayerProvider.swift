import VideoPlayer

class VideoPlayerProvider: NSObject {
    
    typealias ControlView = UIView & VideoPlayerControlViewable
    typealias FinishView = UIView & VideoPlayerFinishViewable
    typealias ErrorView = UIView & VideoPlayerErrorViewable
    typealias CoverView = UIView & VideoPlayerCoverViewable
    
    private(set) weak var player: VideoPlayerable?
    
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
        videoPlayerState(player, state: player.state)
        videoPlayerLoadingState(player, state: player.loading)
        videoPlayerControlState(player, state: player.control)
    }
}

extension VideoPlayerProvider: VideoPlayerDelegate {
    
    func videoPlayerLoadingState(_ player: VideoPlayerable, state: VideoPlayer.LoadingState) {
        switch state {
        case .began:    controlView?.loadingBegin()
        case .ended:    controlView?.loadingEnd()
        }
    }
    
    func videoPlayerControlState(_ player: VideoPlayerable, state: VideoPlayer.ControlState) {
        switch state {
        case .playing:
            controlView?.set(state: true)
            
        case .pausing:
            controlView?.set(state: false)
        }
    }
    
    func videoPlayerState(_ player: VideoPlayerable, state: VideoPlayer.State) {
        switch state {
        case .prepare:
            controlView?.set(enabled: false)
            controlView?.isHidden = false
            finishView?.isHidden = true
            errorView?.isHidden = true
            coverView?.isHidden = true
            
        case .playing:
            controlView?.set(enabled: true)
            controlView?.isHidden = false
            finishView?.isHidden = true
            errorView?.isHidden = true
            coverView?.isHidden = true
            
        case .stopped:
            controlView?.isHidden = true
            finishView?.isHidden = true
            errorView?.isHidden = true
            coverView?.isHidden = false
            
        case .finished:
            controlView?.isHidden = true
            finishView?.isHidden = false
            errorView?.isHidden = true
            coverView?.isHidden = true
            
        case .failure(let error):
            controlView?.isHidden = true
            finishView?.isHidden = true
            errorView?.isHidden = false
            coverView?.isHidden = true
            print(error?.localizedDescription ?? "")
        }
    }
    
    func videoPlayer(_ player: VideoPlayerable, updatedBuffer progress: Double) {
        controlView?.set(buffer: progress, animated: true)
    }
    
    func videoPlayer(_ player: VideoPlayerable, updatedDuration time: Double) {
        controlView?.set(duration: time)
    }
    
    func videoPlayer(_ player: VideoPlayerable, updatedCurrent time: Double) {
        controlView?.set(current: time)
    }
    
    func videoPlayerSeekBegan(_ player: VideoPlayerable) {
        // 可以做一些跳转Toast什么的.
    }
    
    func videoPlayerSeekEnded(_ player: VideoPlayerable) {
        // 跳转结束 隐藏Toast什么的.
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
        // 播放
        player?.play()
        // 恢复视图
        controlView?.isHidden = false
        finishView?.isHidden = true
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
