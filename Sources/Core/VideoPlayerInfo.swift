//
//  VideoPlayerInfo.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//
import MediaPlayer.MPNowPlayingInfoCenter
import MediaPlayer.MPRemoteCommandCenter

public class VideoPlayerInfo: VideoPlayerDelagete {
    
    public var isRemoteEnabled: Bool = true {
        didSet {
            if isRemoteEnabled {
                addRemoteCommand()
            } else {
                removeRemoteCommand()
            }
        }
    }
    
    init() {
        setupRemoteCommand()
        addRemoteCommand()
    }
    
    deinit {
        removeRemoteCommand()
    }
    
    weak var player: VideoPlayerable?
    
    func set(_ player: VideoPlayerable) {
        self.player = player
    }
    
    /// 设置播放信息
    ///
    /// - Parameters:
    ///   - title: 标题
    ///   - artist: 作者
    ///   - thumb: 封面
    ///   - url: 链接
    public func set(title: String, artist: String, thumb: UIImage, url: URL) {
        var info: [String : Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        
        if #available(iOS 10.3, *) {
            // 当前URL
            info[MPNowPlayingInfoPropertyAssetURL] = url
        }
        
        if #available(iOS 10.0, *) {
            // 封面图
            let artwork = MPMediaItemArtwork(
                boundsSize: thumb.size,
                requestHandler: { (size) -> UIImage in
                    return thumb
            })
            info[MPMediaItemPropertyArtwork] = artwork
            // 媒体类型
            info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        } else {
            // 封面图
            let artwork = MPMediaItemArtwork(image: thumb)
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    /// 更新播放信息
    private func updatePlayingInfo() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return
        }
        guard let player = player else { return }
        
        info[MPMediaItemPropertyPlaybackDuration] = player.totalTime ?? 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    /// 清理播放信息
    private func clearPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    public func videoPlayerReady(_ player: VideoPlayerable) {
        updatePlayingInfo()
    }
    
    public func videoPlayerLoadingBegin(_ player: VideoPlayerable) {
        updatePlayingInfo()
    }
    
    public func videoPlayerLoadingEnd(_ player: VideoPlayerable) {
        updatePlayingInfo()
    }
    
    public func videoPlayerPlaying(_ player: VideoPlayerable) {
        updatePlayingInfo()
    }
    
    public func videoPlayerPaused(_ player: VideoPlayerable) {
        updatePlayingInfo()
    }
    
    public func videoPlayerFinish(_ player: VideoPlayerable) {
        updatePlayingInfo()
    }
    
    public func videoPlayer(_ player: VideoPlayerable, updatedTotal time: Double) {
        updatePlayingInfo()
    }
    
    public func videoPlayerSeekFinish(_ player: VideoPlayerable) {
        updatePlayingInfo()
    }
}

extension VideoPlayerInfo {
    
    /// 设置远程控制
    private func setupRemoteCommand() {
        let remote = MPRemoteCommandCenter.shared()
        remote.playCommand.addTarget { [weak self] (event) -> MPRemoteCommandHandlerStatus in
            guard let self = self else { return .commandFailed }
            guard let player = self.player else { return .commandFailed }
            
            switch player.state {
            case .playing: break
            case .paused: player.play()
            case .error, .stopped, .finish: return .noSuchContent
            }
            return .success
        }
        remote.pauseCommand.addTarget { [weak self] (event) -> MPRemoteCommandHandlerStatus in
            guard let self = self else { return .commandFailed }
            guard let player = self.player else { return .commandFailed }
            
            switch player.state {
            case .playing: player.pause()
            case .paused: break
            case .error, .stopped, .finish: return .noSuchContent
            }
            return .success
        }
    }
    /// 添加远程控制
    private func addRemoteCommand() {
        let remote = MPRemoteCommandCenter.shared()
        remote.playCommand.isEnabled = true // 播放控制
        remote.pauseCommand.isEnabled = true // 暂停控制
    }
    /// 移除远程控制
    private func removeRemoteCommand() {
        let remote = MPRemoteCommandCenter.shared()
        remote.playCommand.isEnabled = false // 播放控制
        remote.pauseCommand.isEnabled = false // 暂停控制
    }
}
