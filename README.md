# Backtrace Integration with iOS

<p align="center">
    <img src="https://img.shields.io/badge/platform-iOS%2013%2B%20%7C%20tvOS%2013%2B%20%7C%20macOS%2012%2B-blue.svg" alt="Supported platforms"/>
    <a href="https://masterer.apple.com/swift"><img src="https://img.shields.io/badge/language-swift%205%20%7C%20objective--c-brigthgreen.svg" alt="Supported languages" /></a>
    <a href="https://cocoapods.org/pods/Backtrace"><img src="https://img.shields.io/cocoapods/v/Backtrace.svg?style=flat" alt="CocoaPods compatible" /></a>
    <img src="http://img.shields.io/badge/license-MIT-lightgrey.svg?style=flat" alt="License: MIT" />
    <img src="https://github.com/backtrace-labs/backtrace-cocoa/actions/workflows/test.yml/badge.svg" alt="Build Status" />
</p>

Backtrace's integration with iOS, macOS, and tvOS applications allows you to capture and report handled and unhandled exceptions so you can prioritize and debug software errors.

## Installation 

You can use this SDK through either Swift Package Manager or CocoaPods. The SPM package can be integrated directly within Xcode or by editing your package's Package.swift file.<br>
Choose one of the following integration methods.

### Via Xcode
1. In **File > Add Packages**, search for and add `https://github.com/backtrace-labs/backtrace-cocoa.git`
2. Verify your project **Package Dependencies** list backtrace-cocoa.
3. Add Backtrace to your target’s **Frameworks, Libraries, and Embedded Content**.

### Via Package.swift
Add this dependency to your `Package.swift` file:
```
.package(url: "https://github.com/backtrace-labs/backtrace-cocoa.git)
```

### Via CocoaPods
Add the following to your `Podfile`:
- Specify `use_frameworks!`.
- Add the `Backtrace` pod:

    ```
    pod 'Backtrace'
    ```

### Via Multiplatform Binary Framework Bundle
1. Obtain and Unarchive [Backtrace](https://github.com/backtrace-labs/backtrace-cocoa/releases) binary frameworks
2. Add Backtrace multiplatform binary framework bundle to your project using the method that best fits your workflow:
    * Drag & drop `.framework` or `.xcframework` from Finder into Xcode's Project Navigator and check the Target Membership setting
    * Using Swift Package Manager's `binaryTarget` flag
    * Using CocoaPods's `vendored_frameworks` flag <br><br>

   > **Note:**
   > Backtrace multiplatform binary framework contains Mach-O 64-bit dynamic binaries for iOS, macOS, Mac Catalyst and tvOS.
   > When adding Backtrace to your project, set `Frameworks, Libraries and Embedded Content` section to `Embed`.
   > PLCrashReporter multiplatform binary framework contains static binaries, set `Frameworks, Libraries and Embedded Content` section to `Do Not Embed`.

## Usage
### Swift
https://github.com/backtrace-labs/backtrace-cocoa/blob/8551020be9334f61cd9f27d39a7b4e7d2733d4b0/Examples/Example-iOS/AppDelegate.swift#L21-L41

### Objective-C
https://github.com/backtrace-labs/backtrace-cocoa/blob/8551020be9334f61cd9f27d39a7b4e7d2733d4b0/Examples/Example-iOS-ObjC/AppDelegate.m#L19-L45

## Documentation
For more information about the iOS SDK, including installation, usage, and configuration options, see the [iOS Integration guide](https://docs.saucelabs.com/error-reporting/platform-integrations/ios/setup/) in the Sauce Labs documentation.
