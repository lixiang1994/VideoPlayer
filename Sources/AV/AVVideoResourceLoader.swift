//
//  AVVideoResourceLoader.swift
//  VideoPlayer
//
//  Created by 李响 on 2021/1/15.
//  Copyright © 2021 swift. All rights reserved.
//

import AVFoundation

class AVVideoResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        
        // 未实现数据供给时必须交回系统，返回 true 却不完成请求会让资源永久等待。
        return false
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        
    }
}
