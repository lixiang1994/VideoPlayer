import UIKit

/// Scene 持有界面窗口；播放器自己的前后台通知继续由 UIApplication 统一接收。
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    #if DEBUG
    /// Scene 持有仅在显式测试启动时创建的诊断器。
    private var diagnostics: VideoDeviceDiagnostics?
    #endif

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["VIDEO_DEVICE_DIAGNOSTICS"] == "1", let window = window {
            diagnostics = VideoDeviceDiagnostics(window: window)
        }
        #endif
    }
}
