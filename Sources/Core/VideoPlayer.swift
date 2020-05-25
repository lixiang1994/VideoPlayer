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
            
            DispatchQueue.main.async(execute: completion)
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
            
            DispatchQueue.main.async(execute: completion)
        }
    }
}

extension VideoPlayer {
    
    public class Builder {
        
        typealias Generator = () -> VideoPlayerable
        
        private var generator: Generator
        
        public private(set) lazy var shared = generator()
        
        init(_ generator: @escaping Generator) {
            self.generator = generator
        }
        
        public func instance() -> VideoPlayerable {
            return generator()
        }
    }
}
