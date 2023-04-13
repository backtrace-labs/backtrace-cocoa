# Backtrace Integration with iOS

<p align="center">
    <img src="https://img.shields.io/badge/platform-iOS%2011%2B%20%7C%20tvOS%2011%2B%20%7C%20macOS%2010.13%2B-blue.svg" alt="Supported platforms"/>
    <a href="https://masterer.apple.com/swift"><img src="https://img.shields.io/badge/language-swift%205%20%7C%20objective--c-brigthgreen.svg" alt="Supported languages" /></a>
    <a href="https://cocoapods.org/pods/Backtrace"><img src="https://img.shields.io/cocoapods/v/Backtrace.svg?style=flat" alt="CocoaPods compatible" /></a>
    <img src="http://img.shields.io/badge/license-MIT-lightgrey.svg?style=flat" alt="License: MIT" />
    <img src="https://github.com/backtrace-labs/backtrace-cocoa/actions/workflows/test.yml/badge.svg" alt="Build Status" />
</p>

[Backtrace](http://backtrace.io/)'s integration with iOS, macOS, and tvOS applications allows you to capture and report handled and unhandled exceptions so you can prioritize and debug software errors.

## Installation 

You can use this SDK through either Swift Package Manager or CocoaPods. The SPM package can be integrated directly within Xcode or by editing your package's Package.swift file.<br>
Choose one of the following integration methods.

### Via Xcode
1. In Xcode File > Add Packages, search for `https://github.com/backtrace-labs/backtrace-cocoa.git`
1. In the Dependency Rule list specify the Branch as `SwiftPM`, then click Add Package.
1. Verify your project Package Dependencies list backtrace-cocoa.
1. Be sure to add Backtrace to your target’s Frameworks, Libraries, and Embedded Content.

### Via Package.swift
Add this dependency to your `Package.swift` file:
```
.package(url: "https://github.com/backtrace-labs/backtrace-cocoa.git, branch: "feature/SwiftPM")
```

### Via CocoaPods
Add the Backtrace pod to your `Podfile`:
```
pod 'Backtrace'
```

## Usage
### Swift
https://github.com/backtrace-labs/backtrace-cocoa/blob/8551020be9334f61cd9f27d39a7b4e7d2733d4b0/Examples/Example-iOS/AppDelegate.swift#L21-L41

### Objective-C
https://github.com/backtrace-labs/backtrace-cocoa/blob/8551020be9334f61cd9f27d39a7b4e7d2733d4b0/Examples/Example-iOS-ObjC/AppDelegate.m#L19-L45

## Documentation
For more information about the iOS SDK, including installation, usage, and configuration options, see the [iOS Integration guide](https://docs.saucelabs.com/error-reporting/platform-integrations/ios/setup/) in the Sauce Labs documentation.
