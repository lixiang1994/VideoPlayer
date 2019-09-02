import Foundation

public protocol VideoPlayerDelagete: AnyObject {
    /// 准备完成
    func videoPlayerReady(_ player: VideoPlayerable)
    /// 播放中
    func videoPlayerPlaying(_ player: VideoPlayerable)
    /// 加载开始
    func videoPlayerLoadingBegin(_ player: VideoPlayerable)
    /// 加载结束
    func videoPlayerLoadingEnd(_ player: VideoPlayerable)
    /// 暂停
    func videoPlayerPaused(_ player: VideoPlayerable)
    /// 停止
    func videoPlayerStopped(_ player: VideoPlayerable)
    /// 播放完成
    func videoPlayerFinish(_ player: VideoPlayerable)
    /// 播放错误
    func videoPlayerError(_ player: VideoPlayerable)
    
    /// 更新缓冲进度
    func videoPlayer(_ player: VideoPlayerable, updatedBuffer progress: Double)
    /// 更新总时间 (秒)
    func videoPlayer(_ player: VideoPlayerable, updatedTotal time: Double)
    /// 更新当前时间 (秒)
    func videoPlayer(_ player: VideoPlayerable, updatedCurrent time: Double)
    /// 跳转完成
    func videoPlayerSeekFinish(_ player: VideoPlayerable)
}

public extension VideoPlayerDelagete {
    
    func videoPlayerReady(_ player: VideoPlayerable) { }
    func videoPlayerPlaying(_ player: VideoPlayerable) { }
    func videoPlayerLoadingBegin(_ player: VideoPlayerable) { }
    func videoPlayerLoadingEnd(_ player: VideoPlayerable) { }
    func videoPlayerPaused(_ player: VideoPlayerable) { }
    func videoPlayerStopped(_ player: VideoPlayerable) { }
    func videoPlayerFinish(_ player: VideoPlayerable) { }
    func videoPlayerError(_ player: VideoPlayerable) { }
    
    func videoPlayer(_ player: VideoPlayerable, updatedBuffer progress: Double) { }
    func videoPlayer(_ player: VideoPlayerable, updatedTotal time: Double) { }
    func videoPlayer(_ player: VideoPlayerable, updatedCurrent time: Double) { }
    func videoPlayerSeekFinish(_ player: VideoPlayerable) { }
}
