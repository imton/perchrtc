#
#  Be sure to run `pod spec lint PerchRTC.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

  s.name         = "PerchRTC"
  s.version      = "1.0.6"
  s.summary      = "Easiest way to include WebRTC in iOS."

  # s.description  = <<-DESC
  #                  WebRTC in IOS
  #                  DESC

  s.homepage       = "https://github.com/perchco/perchrtc"

  s.license      = "MIT"

  s.authors      = { "Chris Eagleston" => "chris@perch.co", "Gaston M" => "gaston@black.uy" }

  s.platform     = :ios

  s.source       = { :git => "https://github.com/imton/perchrtc.git", :branch => "gaston", :tag => "1.0.6" }



  # ――― Source Code ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  CocoaPods is smart about how it includes source code. For source files
  #  giving a folder will include any swift, h, m, mm, c & cpp files.
  #  For header files it will include any header in the folder.
  #  Not including the public_header_files will make all headers public.
  #

  s.source_files  = "PerchRTC", "PerchRTC/**/*.{h,m}"

  # s.exclude_files = "Classes/Exclude"
  # s.public_header_files = "Classes/**/*.h"


  # ――― Resources ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  A list of resources included with the Pod. These are copied into the
  #  target bundle with a build phase script. Anything else will be cleaned.
  #  You can preserve files from being cleaned, please don't preserve
  #  non-essential files like tests, examples and documentation.
  #

  # s.resource  = "icon.png"
  # s.resources = "Resources/*.png"

  s.preserve_paths = "PerchRTC", "PerchRTC/**/*.{h,m}"




  # ――― Project Linking ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Link your library with frameworks, or libraries. Libraries do not include
  #  the lib prefix of their name.
  #

  # s.framework  = "SomeFramework"
  # s.frameworks = "SomeFramework", "AnotherFramework"

  # s.library   = "iconv"
  # s.libraries = "iconv", "xml2"


  # ――― Project Settings ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  If your library depends on compiler flags you can set them in the xcconfig hash
  #  where they will only apply to your library. If you depend on other Podspecs
  #  you can include multiple dependencies to ensure it works.

  s.prefix_header_file = 'PerchRTC/PerchRTC-Prefix.pch'

  s.requires_arc = true

  s.xcconfig = { 
    'HEADER_SEARCH_PATHS' => '"$(SRCROOT)"/**'
  }

  s.dependency "CocoaLumberjack", "~> 2.0"
  s.dependency "gaston-nighthawk-webrtc"

  s.subspec 'VideCapture' do |vc| 
    vc.source_files   = 'PerchRTC/CaptureKit/PHVideoCaptureKit.mm', 'PerchRTC/CaptureKit/PHVideoCaptureBridge.mm'
    vc.compiler_flags = '-fno-rtti'
  end  

end
