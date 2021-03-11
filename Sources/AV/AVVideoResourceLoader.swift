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
        
        return true
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        
    }
}
