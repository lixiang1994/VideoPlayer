//
//  VideoPlayerDelegate.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//
import Foundation

public protocol VideoPlayerDelegate: AnyObject {
    /// 加载状态
    func videoPlayerLoadingState(_ player: VideoPlayerable, state: VideoPlayer.LoadingState)
    /// 控制状态
    func videoPlayerControlState(_ player: VideoPlayerable, state: VideoPlayer.ControlState)
    /// 播放状态
    func videoPlayerState(_ player: VideoPlayerable, state: VideoPlayer.State)
    
    /// 更新缓冲进度
    func videoPlayer(_ player: VideoPlayerable, updatedBuffer progress: Double)
    /// 更新总时间 (秒)
    func videoPlayer(_ player: VideoPlayerable, updatedDuration time: Double)
    /// 更新当前时间 (秒)
    func videoPlayer(_ player: VideoPlayerable, updatedCurrent time: Double)
    /// 跳转开始
    func videoPlayer(_ player: VideoPlayerable, seekBegan: VideoPlayer.Seek)
    /// 跳转结束
    func videoPlayer(_ player: VideoPlayerable, seekEnded: VideoPlayer.Seek)
}

public extension VideoPlayerDelegate {
    
    func videoPlayerLoadingState(_ player: VideoPlayerable, state: VideoPlayer.LoadingState) { }
    func videoPlayerControlState(_ player: VideoPlayerable, state: VideoPlayer.ControlState) { }
    func videoPlayerState(_ player: VideoPlayerable, state: VideoPlayer.State) { }
    
    func videoPlayer(_ player: VideoPlayerable, updatedBuffer progress: Double) { }
    func videoPlayer(_ player: VideoPlayerable, updatedDuration time: Double) { }
    func videoPlayer(_ player: VideoPlayerable, updatedCurrent time: Double) { }
    func videoPlayer(_ player: VideoPlayerable, seekBegan: VideoPlayer.Seek) { }
    func videoPlayer(_ player: VideoPlayerable, seekEnded: VideoPlayer.Seek) { }
}
