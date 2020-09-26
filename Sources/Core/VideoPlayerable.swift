//
//  VideoPlayerable.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//
import Foundation

public protocol VideoPlayerable: NSObjectProtocol {
    
    /// 准备播放器 准备完成后自动播放
    @discardableResult
    func prepare(url: URL) -> VideoPlayerView
    /// 播放
    func play()
    /// 暂停
    func pause()
    /// 停止
    func stop()
    /// 快速定位到指定播放时间点 (多次调用 以第一次为准)
    func seek(to time: TimeInterval, completion: @escaping (()->Void))
    
    /// 当前URL
    var url: URL? { get }
    /// 播放器当前状态
    var state: VideoPlayer.State { get }
    /// 播放器加载状态
    var loading: Bool { get }
    /// 当前播放时间
    var currentTime: TimeInterval? { get }
    /// 视频总时长
    var totalTime: TimeInterval? { get }
    /// VideoPlayer 的画面输出到该 UIView 对象
    var view: VideoPlayerView { get }
    
    /// 播放速率
    var rate: Double { get set }
    /// 是否静音
    var isMuted: Bool { get set }
    /// 音量控制
    var volume: Double { get set }
    /// 是否循环播放  默认: false
    var isLoop: Bool { get set }
    /// 是否允许后台播放  默认: false
    var isBackground: Bool { get set }
    /// 是否自动播放  默认: true
    var isAutoPlay: Bool { get set }
    /// 设置播放信息
    var playingInfo: VideoPlayerInfo? { get set }
    /// 设置音频会话队列  默认: .audioSession
    var audioSessionQueue: DispatchQueue { get set }
    
    /// 监听播放回调
    func add(delegate: VideoPlayerDelagete)
    /// 移除监听
    func remove(delegate: VideoPlayerDelagete)
}
