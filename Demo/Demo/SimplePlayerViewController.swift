//
//  SimplePlayerViewController.swift
//  Demo
//
//  Created by Lee on 2019/8/28.
//  Copyright © 2019 swift. All rights reserved.
//

import UIKit
import AVKit
import SnapKit
import VideoPlayer

class SimplePlayerViewController: UIViewController {

    private var type: Int = 0
    
    private var provider: VideoPlayerProvider?
    private lazy var playerView = UIView()
    
    /// 画中画控制器
    private var pictureController: AVPictureInPictureController?
    /// 画中画是否关闭 (用于区分点击了画中画"X"按钮, 还是收起按钮)
    private var isPictureClose = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setup()
    }

    private func setup() {
        view.addSubview(playerView)
        
        playerView.snp.makeConstraints { (make) in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(playerView.snp.width).multipliedBy(9.0 / 16.0)
        }
        
        let url = URL(string: "https://devstreaming-cdn.apple.com/videos/wwdc/2019/808knty6w7kjssfl/808/hls_vod_mvp.m3u8")!
        
        // 初始化播放器
        let player: VideoPlayerable
        switch type {
        case 0:
            player = VideoPlayer.av.instance()
            
        default:
            #if targetEnvironment(simulator)
            player = VideoPlayer.av.instance()
            #else
            player = VideoPlayer.pl.instance()
            #endif
        }
        // 简单设置
        player.isLoop = false
        player.isAutoPlay = true
        player.add(delegate: self)
        
        // 初始化相关视图
        let controlView = VideoPlayerControlView()
        let coverView = VideoPlayerCoverView()
        let errorView = VideoPlayerErrorView()
        let finishView = VideoPlayerFinishView()
        
        view.layoutIfNeeded()
        view.addSubview(controlView)
        view.addSubview(coverView)
        view.addSubview(errorView)
        view.addSubview(finishView)
        
        controlView.snp.makeConstraints { (make) in
            make.edges.equalTo(playerView)
        }
        coverView.snp.makeConstraints { (make) in
            make.edges.equalTo(playerView)
        }
        errorView.snp.makeConstraints { (make) in
            make.edges.equalTo(playerView)
        }
        finishView.snp.makeConstraints { (make) in
            make.edges.equalTo(playerView)
        }
        
        coverView.imageView.image = #imageLiteral(resourceName: "video_cover")
        
        let provider = VideoPlayerProvider(
            control: controlView,
            finish: finishView,
            error: errorView,
            cover: coverView
        ) { [weak self] in
            guard let self = self else { return }
            
            let view = player.prepare(url: url)
            view.backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
            self.playerView.subviews.forEach({ $0.removeFromSuperview() })
            self.playerView.addSubview(view)
            
            view.snp.remakeConstraints({ (make) in
                make.edges.equalToSuperview()
            })
        }
        provider.set(player: player)
        self.provider = provider
    }
    
    private static func instance() -> Self {
        return StoryBoard.main.instance()
    }
    
    static func instance(_ type: Int) -> Self {
        let controller = instance()
        controller.type = type
        return controller
    }
}

extension SimplePlayerViewController {
    
    @objc
    private func startPictureAction() {
        pictureController?.startPictureInPicture()
    }
    
    @objc
    private func stopPictureAction() {
        pictureController?.stopPictureInPicture()
    }
}

extension SimplePlayerViewController: VideoPlayerDelagete {
    
    func videoPlayerReady(_ player: VideoPlayerable) {
        guard
            AVPictureInPictureController.isPictureInPictureSupported(),
            let layer = player.view.playerLayer as? AVPlayerLayer else {
            return
        }
        
        pictureController = AVPictureInPictureController(playerLayer: layer)
        pictureController?.delegate = self
        
        if #available(iOS 14.0, *) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: AVPictureInPictureController.pictureInPictureButtonStartImage,
                style: .plain,
                target: self,
                action: #selector(startPictureAction)
            )
        }
    }
    
    func videoPlayerStopped(_ player: VideoPlayerable) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return
        }
        
        pictureController = nil
        
        navigationItem.rightBarButtonItem = nil
    }
}

/*
 
 全局画中画注意点

 通过一个全局变量持有画中画控制器，可以在pictureInPictureControllerWillStartPictureInPicture持有，pictureInPictureControllerDidStopPictureInPicture释放；
 有可能不是点画中画按钮，而是从其它途径来打开当前画中画控制器，可以在viewWillAppear 进行判断并关闭；
 已有画中画的情况下开启新的画中画，需要等完全关闭完再开启新的，防止有未知的错误出现，因为关闭画中画是有过程的；
 如果创建AVPictureInPictureController并同时开启画中画功能，有可能会失效，出现这种情况延迟开启画中画功能即可。
 
 */

extension SimplePlayerViewController: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("将要开始PictureInPicture的代理方法")
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("已经开始PictureInPicture的代理方法")
        if #available(iOS 14.0, *) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: AVPictureInPictureController.pictureInPictureButtonStopImage,
                style: .plain,
                target: self,
                action: #selector(stopPictureAction)
            )
        }
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("启动PictureInPicture失败的代理方法")
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("将要停止PictureInPicture的代理方法")
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("已经停止PictureInPicture的代理方法")
        if #available(iOS 14.0, *) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: AVPictureInPictureController.pictureInPictureButtonStartImage,
                style: .plain,
                target: self,
                action: #selector(startPictureAction)
            )
        }
        // 处理画中画关闭
        defer { isPictureClose = true }
        guard isPictureClose else { return }
        // 停止播放器
        provider?.player?.stop()
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        //此方法执行在pictureInPictureControllerWillStopPictureInPicture代理方法之后，在pictureInPictureControllerDidStopPictureInPicture执行之前。 但是点击“X”移除画中画时，不执行此方法。
        print("PictureInPicture停止之前恢复用户界面")
        // 设置非画中画关闭
        isPictureClose = false
    }
}
