Pod::Spec.new do |s|
  s.name             = 'camera_desktop'
  s.version          = '1.2.1'
  s.summary          = 'Flutter camera plugin for macOS using AVFoundation.'
  s.description      = <<-DESC
A Flutter camera plugin for desktop platforms. On macOS, uses AVFoundation
for camera capture, preview, photo capture, and video recording.
                       DESC
  s.homepage         = 'https://github.com/hugocornellier/camera_desktop'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Hugo Cornellier' => 'hugo@hugocornellier.com' }
  s.source           = { :http => 'https://github.com/hugocornellier/camera_desktop' }
  s.source_files     = 'camera_desktop/Sources/camera_desktop/**/*.{swift,h,m}'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.15'
  s.swift_version    = '5.0'

  s.resource_bundles = { 'camera_desktop_privacy' => ['camera_desktop/Sources/camera_desktop/PrivacyInfo.xcprivacy'] }

  s.frameworks       = 'AVFoundation', 'CoreMedia', 'CoreVideo', 'CoreImage', 'QuartzCore'
end
