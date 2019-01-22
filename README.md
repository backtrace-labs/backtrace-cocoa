# Backtrace

[Backtrace](http://backtrace.io/)'s integration with iOS and macOS applications allows customers to capture and report handled and unhandled exceptions to their Backtrace instance, instantly offering the ability to prioritise and debug software errors.

<p align="center">
    <img src="https://img.shields.io/badge/platform-iOS%2010%2B%20%7C%20macOS%2010.10%2B-blue.svg" alt="Supported platforms"/>
    <a href="https://masterer.apple.com/swift"><img src="https://img.shields.io/badge/language-swift%204-brightgreen.svg" alt="Language: Swift 4" /></a>
    <a href="https://masterer.apple.com/swift"><img src="https://img.shields.io/badge/language-objective--c-brightgreen.svg" alt="Language: Objecive-C" /></a>
    <a href="https://cocoapods.org/pods/Backtrace"><img src="https://img.shields.io/badge/pod-v1.0.0-blue.svg" alt="CocoaPods compatible" /></a>
    <img src="http://img.shields.io/badge/license-MIT-lightgrey.svg?style=flat" alt="License: MIT" />
    <img src="https://travis-ci.org/backtrace-labs/backtrace-cocoa.svg?branch=master"/>
</p>

## Minimal usage

### Register the `BacktraceClient` using `register(endpoint:,token:)` method and then send error/exception just by calling method `send`:

- Swift
```swift
  import UIKit
  import Backtrace

  @UIApplicationMain
  class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "https://backtrace.io")!,
                                                        token: "token")
        BacktraceClient.shared.register(credentials: backtraceCredentials)

        do {
            // do stuff
        } catch {
            BacktraceClient.shared.send()
        }
        return true
    }
  }
```

- Objective-C
```objective-c
  #import "AppDelegate.h"
  @import Backtrace;

  @interface AppDelegate ()

  @end

  @implementation AppDelegate

  - (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                         initWithEndpoint: [NSURL URLWithString: @"https://backtrace.io"]
                                         token: @"token"];
    [BacktraceClient.shared registerWithCredentials: credentials];

    @try {
        // do stuff
    } @catch (NSException *exception) {
        [[BacktraceClient shared] send];
    } @finally {
        // clean up
    }

    return YES;
  }

  @end
```

# Features Summary <a name="features-summary"></a>
* Light-weight client library written in Swift with full Objective-C support that quickly submits exceptions/errors and crashes to your Backtrace dashboard includes:
  * system metadata,
  * machine metadata,
  * signal metadata,
  * exception metadata,
  * thread metadata,
  * process metadata.
* Supports iOS and macOS platforms.
* Swift first protocol-oriented framework.

# Installation <a name="installation"></a>

## via CocoaPods

To use [CocoaPods](https://cocoapods.org) just add this to your Podfile:

```
pod 'Backtrace'
```

**Note:** It is required to specify `use_frameworks!` in your Podfile.

# Documentation  <a name="documentation"></a>

## Register with Backtrace credentials<a name="documentation-initialization"></a>

Register to Backtrace services using provided submission url (see: <a href="https://help.backtrace.io/troubleshooting/what-is-a-submission-url">What is a submission url?</a>) and token (see: <a href="https://help.backtrace.io/troubleshooting/what-is-a-submission-token">What is a submission token?</a>).

- Swift
```swift
BacktraceClient.shared.register(credentials: BacktraceCredentials)
```
- Objective-C
```objective-c
[[BacktraceClient shared] registerWithCredentials: BacktraceCredentials];
```

## Sending an error report <a name="documentation-sending-report"></a>
Registered `BacktraceClient` will be able to send an crash reports.

### Sending `Error/NSError/NSException`
- Swift
```swift
@objc func send(completion: ((BacktraceResult) -> Void))
@objc func send()
```
- Objective-C
```objective-c
 - (void) sendWithCompletion: (void (^)(BacktraceResult * _Nonnull)) completion;
 - (void) send;
```

# Architecture  <a name="architecture"></a>

The library is written in pure Swift and Objective-C is fully supported as Swift codebase can be automatically exposed just by adding annotations:

```swift
// pure swift class - cannot be exposed to Objective-C
class PureSwiftClass {

}

// swift class with Objective-C support
@objc class SwiftClass: NSObject {

}
```

As Swift is meant to be open-source and platform independent the library relies on `protocols` which allows to provide default implementation but simultaneously gives you a lot of place for customisation.

# FAQ
## Missing dSYM files
Make sure your project is configured to generate the debug symbols:
* Go to your project target's build settings: `YourTarget -> Build Settings`.
* Search for `Debug Information Format`.
* Select `DWARF with dSYM File`.
![alt text](https://github.com/backtrace-labs/backtrace-cocoa/blob/master/docs/screenshots/xcode-debug-information-format.png)

### Finding dSYMs while building project
* Build the project.
* Build products and dSYMs are placed into the `Products` directory.
![alt text](https://github.com/backtrace-labs/backtrace-cocoa/blob/master/docs/screenshots/xcode-products.png)
![alt text](https://github.com/backtrace-labs/backtrace-cocoa/blob/master/docs/screenshots/finder-dsyms-products.png)
* Zip all the `dSYM` files and upload to Backtrace services (see: <a href="https://help.backtrace.io/product-guide/symbolification">Symbolification</a>)

### Finding dSYMs while archiving project
* Archive the project.
* dSYMs are placed inside of an `.xcarchive` of your project.
* Open Xcode -> Window -> Organizer
* Click on archive and select `Show in Finder`
![alt text](https://github.com/backtrace-labs/backtrace-cocoa/blob/master/docs/screenshots/xcode-organizer.png)
* Click on `Show Package Contents`
![alt text](https://github.com/backtrace-labs/backtrace-cocoa/blob/master/docs/screenshots/finder-xcarchive.png)
* Search for `dSYMs` directory
![alt text](https://github.com/backtrace-labs/backtrace-cocoa/blob/master/docs/screenshots/finder-dsyms-archive.png)
* Zip all the `dSYM` files and upload to Backtrace services (see: <a href="https://help.backtrace.io/product-guide/symbolification">Symbolification</a>)
