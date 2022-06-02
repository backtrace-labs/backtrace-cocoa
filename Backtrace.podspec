#
#  Be sure to run `pod spec lint Backtrace.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

  s.name         = "Backtrace"
  s.version      = "1.7.2"
  s.summary      = "Backtrace's integration with iOS, macOS and tvOS"
  s.description  = "Reliable crash and hang reporting for iOS, macOS and tvOS."
  s.homepage     = "https://backtrace.io/"
  s.license      = { :type => "MIT", :file => 'LICENSE' }
  s.author       = { "Backtrace I/O" => "info@backtrace.io" }
  s.source       = { :git => "https://github.com/backtrace-labs/backtrace-cocoa.git", :tag => "#{s.version}" }

  s.ios.deployment_target = "10.0"
  s.osx.deployment_target = "10.10"
  s.tvos.deployment_target = "10.0"

  s.ios.source_files = ["Sources/**/*.{swift}", "Backtrace-iOS/**/*.{h*,swift}"]
  s.osx.source_files = ["Sources/**/*.{swift}", "Backtrace-macOS/**/*.{h*,swift}"]
  s.tvos.source_files = ["Sources/**/*.{swift}", "Backtrace-tvOS/**/*.{h*,swift}"]

  s.ios.public_header_files = ["Backtrace-iOS/**/*.h*"]
  s.osx.public_header_files = ["Backtrace-macOS/**/*.h*"]
  s.tvos.public_header_files = ["Backtrace-tvOS/**/*.h*"]

  s.dependency "PLCrashReporter"
  s.resources = 'Sources/**/*.xcdatamodeld'
  s.static_framework = true
  s.swift_version = '4.2'
end
