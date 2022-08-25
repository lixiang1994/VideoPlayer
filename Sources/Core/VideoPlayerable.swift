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

public protocol VideoPlayerURLAsset {
    var value: URL { get }
}

public protocol VideoPlayerable: NSObjectProtocol {
    
    /// 准备
    @discardableResult
    func prepare(resource: VideoPlayerURLAsset) -> VideoPlayerView
    /// 播放
    func play()
    /// 暂停
    func pause()
    /// 停止
    func stop()
    /// 快速定位到指定播放时间点 (多次调用 以最后一次为准)
    func seek(to target: VideoPlayer.Seek)
    
    /// 资源
    var resource: VideoPlayerURLAsset? { get }
    /// 播放器当前状态
    var state: VideoPlayer.State { get }
    /// 播放器控制状态
    var control: VideoPlayer.ControlState { get }
    /// 播放器加载状态
    var loading: VideoPlayer.LoadingState { get }
    
    /// 当前时间
    var current: TimeInterval { get }
    /// 视频总时长
    var duration: TimeInterval { get }
    /// 缓冲进度 0 - 1
    var buffer: Double { get }
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
    
    /// 播放配置
    var configuration: VideoPlayerConfiguration { get }
    
    /// 添加委托
    func add(delegate: VideoPlayerDelegate)
    /// 移除委托
    func remove(delegate: VideoPlayerDelegate)
    /// 截图 获取当前播放的画面截图
    func screenshot(completion: @escaping (UIImage?) -> Void)
}

extension URL: VideoPlayerURLAsset {
    
    public var value: URL {
        return self
    }
}
