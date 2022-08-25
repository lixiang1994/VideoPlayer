//
//  VideoPlayer.swift
//  ┌─┐      ┌───────┐ ┌───────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ │      │ └─────┐ │ └─────┐
//  │ │      │ ┌─────┘ │ ┌─────┘
//  │ └─────┐│ └─────┐ │ └─────┐
//  └───────┘└───────┘ └───────┘
//
import Foundation
import UIKit
import AVFoundation

public enum VideoPlayer {
    /// 播放状态
    /// stopped -> prepare -> playing -> finished
    public enum State {
        /// 准备播放: 调用`prepare(resource:)`后的状态.
        case prepare
        /// 正在播放: `prepare`处理完成后的状态,  当`finished`状态时再次调用`play()`也会回到该状态.
        case playing
        /// 播放停止: 默认的初始状态, 调用`stop()`后的状态.
        case stopped
        /// 播放完成: 在`isLoop = false`时会触发.
        case finished
        /// 播放失败: 调用`prepare(resource:)`后的任何时候 只要发生了异常便会触发该状态.
        case failed(Swift.Error?)
    }
    
    /// 控制状态: 仅在 state 为 .playing 状态时可用
    public enum ControlState {
        /// 播放中
        case playing
        /// 暂停中
        case pausing
    }
    
    /// 加载状态
    public enum LoadingState {
        /// 已开始
        case began
        /// 已结束
        case ended
    }
    
    public struct Seek {
        /// 目标时间 (秒)
        public let time: TimeInterval
        /// 完成回调 (成功为true, 失败为false, 失败可能是由于网络问题或被其他Seek抢占导致的)
        let completion: ((Bool) -> Void)?
        
        public init(time: TimeInterval, completion: ((Bool) -> Void)? = .none) {
            self.time = time
            self.completion = completion
        }
    }
}

public extension VideoPlayer {
    
    static func setupAudioSession(in queue: DispatchQueue, with completion: @escaping (() -> Void) = {}) {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        queue.async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true, options: [.notifyOthersOnDeactivation])
            } catch {
                print("音频会话创建失败")
            }
            
            DispatchQueue.sync(safe: .main, execute: completion)
        }
    }
    
    static func removeAudioSession(in queue: DispatchQueue, with completion: @escaping (() -> Void) = {}) {
        UIApplication.shared.endReceivingRemoteControlEvents()
        queue.async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                print("音频会话释放失败")
            }
            
            DispatchQueue.sync(safe: .main, execute: completion)
        }
    }
}

extension VideoPlayer {
    
    public class Builder {
        
        public typealias Generator = (VideoPlayerConfiguration) -> VideoPlayerable
        
        private var generator: Generator
        
        public private(set) lazy var shared = generator(.init())
        
        public init(_ generator: @escaping Generator) {
            self.generator = generator
        }
        
        public func instance(_ configuration: VideoPlayerConfiguration = .init()) -> VideoPlayerable {
            return generator(configuration)
        }
    }
}

extension DispatchQueue {
    
    public static let audioSession: DispatchQueue = .init(label: "com.audio.session.queue")
}

extension DispatchQueue {
    
    private static func isCurrent(_ queue: DispatchQueue) -> Bool {
        let key = DispatchSpecificKey<Void>()
        
        queue.setSpecific(key: key, value: ())
        defer { queue.setSpecific(key: key, value: nil) }
        
        return getSpecific(key: key) != nil
    }
    
    /// 安全同步执行 (可防止死锁)
    /// - Parameter queue: 队列
    /// - Parameter work: 执行
    static func sync(safe queue: DispatchQueue, execute work: () -> Void) {
        isCurrent(queue) ? work() : queue.sync(execute: work)
    }
}
