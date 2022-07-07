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
    private lazy var statusView = UIView()
    
    private let pip = PictureInPicture()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setup()
    }

    private func setup() {
        view.addSubview(playerView)
        
        playerView.snp.makeConstraints { (make) in
            if #available(iOS 11.0, *) {
                make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
                
            } else {
                make.top.equalTo(topLayoutGuide.snp.bottom)
            }
            make.left.right.equalToSuperview()
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
        view.addSubview(statusView)
        statusView.addSubview(controlView)
        statusView.addSubview(coverView)
        statusView.addSubview(errorView)
        statusView.addSubview(finishView)
        
        statusView.snp.makeConstraints { (make) in
            make.edges.equalTo(playerView)
        }
        controlView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        coverView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        errorView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        finishView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
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
            
            view.snp.remakeConstraints { (make) in
                make.edges.equalToSuperview()
            }
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
        pip.start()
    }
    
    @objc
    private func stopPictureAction() {
        pip.stop()
    }
}

extension SimplePlayerViewController: VideoPlayerDelegate {
    
    func videoPlayerControlState(_ player: VideoPlayerable, state: VideoPlayer.ControlState) {
        pip.invalidatePlaybackState()
    }
    
    func videoPlayerState(_ player: VideoPlayerable, state: VideoPlayer.State) {
        switch state {
        case .playing:
            guard
                pip.isSuspended,
                let layer = player.view.playerLayer as? AVPlayerLayer else {
                return
            }
            // 播放中时 设置画中画
            pip.setup(player: layer)
            pip.delegate = self
            
            if #available(iOS 14.0, *) {
                navigationItem.rightBarButtonItem = UIBarButtonItem(
                    image: AVPictureInPictureController.pictureInPictureButtonStartImage,
                    style: .plain,
                    target: self,
                    action: #selector(startPictureAction)
                )
            }
            
        case .finished, .stopped, .failure:
            // 不在播放中时 则关闭画中画
            pip.close()
            
            navigationItem.rightBarButtonItem = nil
            
        default:
            break
        }
    }
}

extension SimplePlayerViewController: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // 已经开始PictureInPicture
        // 隐藏视图
        statusView.isHidden = true
        
        if #available(iOS 14.0, *) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: AVPictureInPictureController.pictureInPictureButtonStopImage,
                style: .plain,
                target: self,
                action: #selector(stopPictureAction)
            )
        }
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // 将要停止PictureInPicture的代理方法
        // 显示视图
        statusView.isHidden = false
        
        if #available(iOS 14.0, *) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: AVPictureInPictureController.pictureInPictureButtonStartImage,
                style: .plain,
                target: self,
                action: #selector(startPictureAction)
            )
        }
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // 已经停止PictureInPicture的代理方法
        // 停止播放器
        provider?.player?.stop()
    }
}
