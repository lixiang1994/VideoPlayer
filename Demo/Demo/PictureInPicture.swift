//
//  PictureInPicture.swift
//  Demo
//
//  Created by 李响 on 2022/5/16.
//  Copyright © 2022 swift. All rights reserved.
//

import AVKit

/// Demo 的 PiP 生命周期桥接；转发真实事件，旧控制器的迟到事件不能影响新会话。
class PictureInPicture: NSObject {
    
    weak var delegate: AVPictureInPictureControllerDelegate?
    
    var isSuspended: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }
    var isActive: Bool {
        pictureController?.isPictureInPictureActive ?? false
    }
    
    /// 画中画控制器
    private(set) var pictureController: AVPictureInPictureController?
    /// 画中画是否关闭 (用于区分点击了画中画"X"按钮, 还是收起按钮)
    private(set) var isPictureClose = true
    /// 当前绑定的画面层；桥接器不额外延长其生命周期。
    private(set) weak var player: AVPlayerLayer?

    /// 绑定系统控制器。Scene 激活也可能来自 PiP 自身转场，不能据此自动收起画中画。
    func setup(player: AVPlayerLayer) {
        guard isSuspended else { return }
        
        guard self.player !== player || pictureController == nil else { return }
        close()
        self.player = player
        isPictureClose = true
        if #available(iOS 15.0, *) {
            pictureController = AVPictureInPictureController(contentSource: .init(playerLayer: player))
            
        } else {
            pictureController = AVPictureInPictureController(playerLayer: player)
        }
        
        if #available(iOS 14.2, *) {
            pictureController?.canStartPictureInPictureAutomaticallyFromInline = true
        }
        
        pictureController?.delegate = self
    }
    
    func close() {
        pictureController?.delegate = nil
        pictureController?.stopPictureInPicture()
        pictureController = nil
        player = nil
    }
    
    func invalidatePlaybackState() {
        guard isSuspended else { return }
        if #available(iOS 15.0, *) {
            pictureController?.invalidatePlaybackState()
        }
    }
    
    func start() {
        guard isSuspended else { return }
        pictureController?.startPictureInPicture()
    }
    
    func stop() {
        guard isSuspended else { return }
        isPictureClose = false
        pictureController?.stopPictureInPicture()
    }

    deinit {
        pictureController?.delegate = nil
        pictureController?.stopPictureInPicture()
    }
}

/*
 
 全局画中画注意点

 通过一个全局变量持有画中画控制器，可以在pictureInPictureControllerWillStartPictureInPicture持有，pictureInPictureControllerDidStopPictureInPicture释放；
 有可能不是点画中画按钮，而是从其它途径来打开当前画中画控制器，可以在viewWillAppear 进行判断并关闭；
 已有画中画的情况下开启新的画中画，需要等完全关闭完再开启新的，防止有未知的错误出现，因为关闭画中画是有过程的；
 如果创建AVPictureInPictureController并同时开启画中画功能，有可能会失效，出现这种情况延迟开启画中画功能即可。
 
 */

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard self.pictureController === pictureInPictureController else { return }
        delegate?.pictureInPictureControllerWillStartPictureInPicture?(pictureInPictureController)
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard self.pictureController === pictureInPictureController else { return }
        delegate?.pictureInPictureControllerDidStartPictureInPicture?(pictureInPictureController)
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard self.pictureController === pictureInPictureController else { return }
        delegate?.pictureInPictureController?(pictureInPictureController, failedToStartPictureInPictureWithError: error)
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard self.pictureController === pictureInPictureController else { return }
        delegate?.pictureInPictureControllerWillStopPictureInPicture?(pictureInPictureController)
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard self.pictureController === pictureInPictureController else { return }
        // 处理画中画关闭
        defer { isPictureClose = true }
        // 停止事件必须转发 didStop；关闭与恢复 UI 的业务含义由调用方读取 isPictureClose 区分。
        delegate?.pictureInPictureControllerDidStopPictureInPicture?(pictureInPictureController)
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        guard self.pictureController === pictureInPictureController else { completionHandler(false); return }
        // 恢复成功必须由界面持有者确认，不能在页面已经消失时向系统谎报成功。
        guard let delegate = delegate,
              delegate.responds(to: #selector(AVPictureInPictureControllerDelegate.pictureInPictureController(_:restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:))) else {
            completionHandler(false)
            return
        }
        delegate.pictureInPictureController?(pictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler: { [weak self] restored in
            guard let self = self, self.pictureController === pictureInPictureController else {
                completionHandler(false)
                return
            }
            if restored { self.isPictureClose = false }
            completionHandler(restored)
        })
    }
}
