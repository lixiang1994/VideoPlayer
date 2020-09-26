Pod::Spec.new do |s|

s.name         = "VideoPlayer"
s.version      = "1.1.4"
s.summary      = "视频播放器"

s.homepage     = "https://github.com/lixiang1994/VideoPlayer"

s.license      = { :type => "MIT", :file => "LICENSE" }

s.author       = { "LEE" => "18611401994@163.com" }

s.platform     = :ios, "10.0"

s.source       = { :git => "https://github.com/lixiang1994/VideoPlayer.git", :tag => s.version }

s.requires_arc = true

s.frameworks = 'UIKit', 'Foundation', 'AVFoundation', 'MediaPlayer'

s.swift_version = '5.0'

s.default_subspec = 'Core', 'AVPlayer'

s.subspec 'Core' do |sub|
sub.source_files  = 'Sources/Core/*.swift'
end

s.subspec 'AVPlayer' do |sub|
sub.dependency 'VideoPlayer/Core'
sub.source_files = 'Sources/AV/*.swift'
end

s.subspec 'PLPlayer' do |sub|
sub.dependency 'VideoPlayer/Core'
sub.source_files = 'Sources/PL/*.swift'
sub.dependency 'PLPlayerKit', '3.4.3'
end

end
