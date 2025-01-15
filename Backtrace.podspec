#
#  Be sure to run `pod spec lint Backtrace.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

  s.name         = "Backtrace"
  s.version      = "2.0.7"
  s.swift_version = '5'
  s.summary      = "Backtrace's integration with iOS, macOS and tvOS"
  s.description  = "Reliable crash and hang reporting for iOS, macOS and tvOS."
  s.homepage     = "https://backtrace.io/"
  s.license      = { :type => "MIT", :file => 'LICENSE' }
  s.author       = { "Backtrace I/O" => "info@backtrace.io" }
  s.source       = { :git => "https://github.com/backtrace-labs/backtrace-cocoa.git", :tag => "#{s.version}" }

  s.ios.deployment_target = "12.0"
  s.osx.deployment_target = "10.13"
  s.tvos.deployment_target = "12.0"

  s.ios.source_files = ["Sources/**/*.{swift}", "Backtrace-iOS/**/*.{h*,swift}"]
  s.osx.source_files = ["Sources/**/*.{swift}", "Backtrace-macOS/**/*.{h*,swift}"]
  s.tvos.source_files = ["Sources/**/*.{swift}", "Backtrace-tvOS/**/*.{h*,swift}"]
  
  s.tvos.exclude_files = ["Sources/Features/Breadcrumb/**/*.{swift}"]
  
  s.ios.public_header_files = ["Backtrace-iOS/**/*.h*"]
  s.osx.public_header_files = ["Backtrace-macOS/**/*.h*"]
  s.tvos.public_header_files = ["Backtrace-tvOS/**/*.h*"]
  s.static_framework = true
  s.dependency "PLCrashReporter", '1.11.2rc'
  s.resource_bundle = { 'BacktraceResources' => ['Sources/**/*.xcdatamodeld','Sources/Resources/*.xcprivacy']}

end
