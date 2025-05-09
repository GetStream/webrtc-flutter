#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'stream_webrtc_flutter'
  s.version          = '1.0.3'
  s.summary          = 'Flutter WebRTC plugin for iOS.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'https://github.com/GetStream/webrtc-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'getstream.io' => 'support@getstream.io' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.ios.deployment_target = '13.0'
  s.static_framework = true
  s.vendored_frameworks = 'Frameworks/StreamWebRTC.xcframework'
  s.prepare_command = <<-CMD
    mkdir -p Frameworks/
    curl -sL "https://github.com/GetStream/stream-video-swift-webrtc/releases/download/125.6422.070/StreamWebRTC.xcframework.zip" -o Frameworks/StreamWebRTC.zip
    unzip -o Frameworks/StreamWebRTC.zip -d Frameworks/
    rm Frameworks/StreamWebRTC.zip
  CMD
end
