#
#  Be sure to run `pod spec lint Backtrace.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

  s.name         = "Backtrace"
  s.version      = "0.0.1"
  s.summary      = "Backtrace's integration with iOS and macOS"
  s.description  = "Backtrace's integration with iOS and macOS for handling crashes"
  s.homepage     = "https://backtrace.io/"
  s.license      = "MIT"
  s.author             = { "Marcin Karmelita" => "marcin@apptailors.co" }
  s.source       = { :git => "git@github.com:apptailors/backtrace.git", :tag => "#{s.version}" }

  s.ios.deployment_target = "10.0"
  s.osx.deployment_target = "10.10"
  
  s.ios.source_files  = ["Sources/**/*.{swift}", "Backtrace-iOS/**/*.h*"]
  s.osx.source_files = ["Sources/**/*.{swift}", "Backtrace-macOS/**/*.h*"]

  s.ios.public_header_files = ["Backtrace-iOS/**/*.h*"]
  s.osx.public_header_files = ["Backtrace-macOS/**/*.h*"]

  s.dependency "PLCrashReporter"

end
