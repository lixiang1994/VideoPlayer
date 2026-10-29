//
//  VideoPlayerConfiguration.swift
//  VideoPlayer
//
//  Created by 李响 on 2022/7/22.
//  Copyright © 2022 swift. All rights reserved.
//

import Foundation

public struct VideoPlayerConfiguration {
    
    /// 是否由 AVPlayer 后端处理音频会话中断、输出路由断开及媒体服务重置；默认 true。
    /// 宿主统一处理这三类通知时设为 false；不影响 App 前后台和当前 item 的通知。
    public var handlesAudioSessionNotifications: Bool = true

    /// 是否自动播放 默认: true
    public var isAutoplay: Bool = true
    
    /// 预缓冲时长 默认 0 自动选择
    public var preferredBufferDuration: TimeInterval = 0
    
    /// 当前时间回调周期间隔 每秒次数 默认: 每秒10次
    public var currentTimeCallbackPeriodicInterval: UInt = 10
    
    public init() {
        
    }
}
