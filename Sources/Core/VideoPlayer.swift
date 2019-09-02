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
    
    static func setupAudioSession() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        DispatchQueue.global().async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true, options: [.notifyOthersOnDeactivation])
            } catch {
                print("音频会话创建失败")
            }
        }
    }
    
    static func removeAudioSession() {
        UIApplication.shared.endReceivingRemoteControlEvents()
        DispatchQueue.global().async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                print("音频会话释放失败")
            }
        }
    }
}

extension VideoPlayer {
    
    public class Builder {
        
        typealias Generator = () -> VideoPlayerable
        
        private var generator: Generator
        
        private(set) lazy var shared = generator()
        
        init(_ generator: @escaping Generator) {
            self.generator = generator
        }
        
        public func instance() -> VideoPlayerable {
            return generator()
        }
    }
}
