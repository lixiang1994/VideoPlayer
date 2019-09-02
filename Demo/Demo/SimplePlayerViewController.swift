//
//  SimplePlayerViewController.swift
//  Demo
//
//  Created by Lee on 2019/8/28.
//  Copyright © 2019 swift. All rights reserved.
//

import UIKit
import SnapKit
import VideoPlayer

class SimplePlayerViewController: UIViewController {

    private var type: Int = 0
    
    private var provider: VideoPlayerProvider?
    private lazy var playerView = UIView()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.addSubview(playerView)
        
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
            player = VideoPlayer.pl.instance()
        }
        // 简单设置
        player.isLoop = false
        player.isAutoPlay = true
        player.isBackground = true
        
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
