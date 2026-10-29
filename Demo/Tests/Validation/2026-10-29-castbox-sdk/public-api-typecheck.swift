import Foundation
import VideoPlayer

func createHostManagedPlayer() -> VideoPlayerable {
    var configuration = VideoPlayerConfiguration()
    configuration.isAutoplay = false
    configuration.handlesAudioSessionNotifications = false
    return VideoPlayer.av.instance(configuration)
}

func sampleNativePlayback(_ player: VideoPlayerable) -> (TimeInterval?, Bool, Double, TimeInterval)? {
    guard let monitoring = player as? AVVideoNativePlaybackMonitoring else { return nil }
    let sample: AVVideoNativePlaybackSample = monitoring.nativePlaybackSample
    return (sample.position, sample.seekPending, sample.rate, sample.sampledAt)
}
