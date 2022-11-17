//
//  PictureInPicture.swift
//  Demo
//
//  Created by 李响 on 2022/5/16.
//  Copyright © 2022 swift. All rights reserved.
//

import AVKit

class PictureInPicture: NSObject {
    
    weak var delegate: AVPictureInPictureControllerDelegate?
    
    var isSuspended: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }
    var isActive: Bool {
        pictureController?.isPictureInPictureActive ?? false
    }
    
    /// 画中画控制器
    private var pictureController: AVPictureInPictureController?
    /// 画中画是否关闭 (用于区分点击了画中画"X"按钮, 还是收起按钮)
    private var isPictureClose = true
    
    private(set) weak var player: AVPlayerLayer?
    
    override init() {
        super.init()
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] sender in
            guard let self = self else { return }
            guard self.isSuspended, self.isActive else { return }
            // 从后台回来 延迟1秒自动停止画中画
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.pictureController?.stopPictureInPicture()
            }
        }
    }
    
    func setup(player: AVPlayerLayer) {
        guard isSuspended else { return }
        
        self.player = player
        
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
        guard isSuspended else { return }
        pictureController = nil
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
        print("将要开始PictureInPicture的代理方法")
        delegate?.pictureInPictureControllerWillStartPictureInPicture?(pictureInPictureController)
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("已经开始PictureInPicture的代理方法")
        delegate?.pictureInPictureControllerDidStartPictureInPicture?(pictureInPictureController)
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("启动PictureInPicture失败的代理方法")
        delegate?.pictureInPictureController?(pictureInPictureController, failedToStartPictureInPictureWithError: error)
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("将要停止PictureInPicture的代理方法")
        delegate?.pictureInPictureControllerWillStopPictureInPicture?(pictureInPictureController)
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("已经停止PictureInPicture的代理方法")
        // 处理画中画关闭
        defer { isPictureClose = true }
        guard isPictureClose else { return }
        delegate?.pictureInPictureControllerWillStartPictureInPicture?(pictureInPictureController)
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        print("PictureInPicture停止之前恢复用户界面")
        isPictureClose = false
        
        // 设置非画中画关闭
        completionHandler(true)
    }
}
