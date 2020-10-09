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
    public enum State {
        /// 播放中
        case playing
        /// 已暂停
        case paused
        /// 停止
        case stopped
        /// 播放完成
        case finish
        /// 播出出错
        case error
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
        
        public typealias Generator = () -> VideoPlayerable
        
        private var generator: Generator
        
        public private(set) lazy var shared = generator()
        
        public init(_ generator: @escaping Generator) {
            self.generator = generator
        }
        
        public func instance() -> VideoPlayerable {
            return generator()
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
