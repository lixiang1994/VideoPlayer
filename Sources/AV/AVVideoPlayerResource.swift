//
//  AVVideoPlayerResource.swift
//  VideoPlayer
//

import AVFoundation

/// AVPlayer 视频资源，将视频 asset 与针对其音轨创建的混合配置一起提交。
/// 音轨加载及 mix/tap 构建由调用方完成；播放器不负责音效算法或视频合成，也不保证所有流媒体支持处理。
public struct AVVideoPlayerResource: VideoPlayerURLAsset {
    
    /// 实际用于创建 AVPlayerItem 的同一个资源，保留其加载选项及音轨身份。
    public let asset: AVURLAsset
    
    /// 初始化时复制的混合配置；nil 使用系统默认处理，切资源不会继承上一份 mix。
    /// 复制配置不隔离 tap 内部的处理状态；状态同步及实时音频线程安全仍由调用方负责。
    public let audioMix: AVAudioMix?
    
    /// 提供通用资源协议所需的 URL；AVPlayer 后端会直接使用 asset，不根据 URL 重建资源。
    public var value: URL {
        return asset.url
    }
    
    /// 保存 asset 并复制 mix；input parameters 必须针对该 asset 的音轨创建。
    /// 构建完成后在主线程调用播放器的 prepare；后续修改原 mix 不会更新已创建的资源。
    public init(asset: AVURLAsset, audioMix: AVAudioMix? = nil) {
        self.asset = asset
        self.audioMix = audioMix?.copy() as? AVAudioMix
    }
}

/// AVPlayer 后端的混合配置能力；通过能力转换使用，不要求其他播放器实现 AVFoundation API。
public protocol AVVideoAudioMixControlling: VideoPlayerable {
    /// 当前 item 实际使用的配置；resource 中的 mix 仍是准备时的快照。
    var audioMix: AVAudioMix? { get }

    /// 主线程同步更新当前 item 的 mix，nil 移除处理；不 prepare、seek 或改变播放意图。
    /// asset 必须与当前 item 的 asset 是同一实例；无资源或身份不符返回 false，不缓存到下一首。
    /// true 仅表示配置已提交，不保证 HLS、受保护内容或输出路由支持处理。
    /// 任意 mix 替换可能触发系统处理链重配置；频繁切换增益应复用已安装的 tap 更新处理参数。
    @discardableResult
    func update(audioMix: AVAudioMix?, for asset: AVURLAsset) -> Bool
}
