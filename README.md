# Backtrace

[Backtrace](http://backtrace.io/)'s integration with iOS and macOS applications allows customers to capture and report handled and unhandled exceptions to their Backtrace instance, instantly offering the ability to prioritize and debug software errors.

<p align="center">
    <img src="https://img.shields.io/badge/platform-iOS%208%2B-blue.svg?style=flat" alt="Platform: iOS 8+"/>
    <a href="https://developer.apple.com/swift"><img src="https://img.shields.io/badge/language-swift%204-brightgreen.svg" alt="Language: Swift 4" /></a>
    <a href="https://developer.apple.com/swift"><img src="https://img.shields.io/badge/language-swift%203-4BC51D.svg?style=flat" alt="Language: Swift 3" /></a>
    <a href="https://developer.apple.com/swift"><img src="https://img.shields.io/badge/language-objective--c-brightgreen.svg" alt="Language: Objecive-C" /></a>
    <a href="https://github.com/Carthage/Carthage"><img src="https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat" alt="Carthage compatible" /></a>
    <a href="https://cocoapods.org"><img src="https://img.shields.io/badge/pod-v1.0.0-blue.svg" alt="CocoaPods compatible" /></a>
    <img src="http://img.shields.io/badge/license-MIT-lightgrey.svg?style=flat" alt="License: MIT" /> <br><br>
</p>

## Minimal usage

### Register the `Backtrace` using `register(endpoint:,token:)` method and then send error/exception just by calling method `send`:

- Swift
```swift
  import UIKit
  import Backtrace

  @UIApplicationMain
  class AppDelegate: UIResponder, UIApplicationDelegate {

      func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
          Backtrace.register(endpoint: "backtraceEndpoint", token: "backtraceToken")
          return true
      }
  }
```
```swift
do {
    // throw error
} catch {
    BacktraceClient.send(error)
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
      [Backtrace registerWithEndpoint: @"backtraceEndpoint" andToken: @"backtraceToken"];
      return YES;
  }
  @end
```

  ```objective-c
    // handling exceptions
    @try {
        // throw exception
    } @catch (NSException *exception) {
        [BacktraceClient sendException: exception];
    }
  ```
  ```objective-c
    // handling errors
    [webService makeAPICall:^(NSString response, NSError *error) {
        if (error) {
            [BacktraceClient sendError: error];
            return;
        }
        // ...
    }];
  ```

# Table of contents
1. [Features Summary](#features-summary)
2. [Installation](#installation)
3. [Documentation](#documentation)
    1. [Initialize new BacktraceClient](#documentation-initialization)
        * [Database Initialization](#documentation-database-initialization)
    2. [Sending a report](#documentation-sending-report)
    3. [Events](#documentation-events)
    4. [Customization](#documentation-customization)
4. [Architecture](#architecture)

# Features Summary <a name="features-summary"></a>
* Light-weight client library written in Swift with full Objective-C support that quickly submits exceptions/errors and crashes to your Backtrace dashboard
  * Can include callstack, system metadata, custom metadata, and file attachments if needed.
* Supports all Apple platforms (iOS, macOS, watchOS, tvOS).
* [Experimental] Supports Swift on server-side
* Swift first protocol-oriented framework
* Supports synchronous/asynchronous report sending.
* Supports offline database for error report storage and re-submission in case of network outage.

# Installation <a name="installation"></a>

## via Carthage

You can use [Carthage](https://github.com/Carthage/Carthage) to install Backtrace by adding this to your Cartfile:

#### Swift 4
```
github "Backtrace/Backtrace"
```

#### Swift 3

```
github "Backtrace/Backtrace" ~> 0.3
```

## via CocoaPods

To use [CocoaPods](https://cocoapods.org) just add this to your Podfile:

#### Swift 4

```
pod 'Backtrace'
```

#### Swift 3

```
pod 'Backtrace', '~> 0.3.0'
```

## or Download

1. Download the latest source code.
2. Drag & drop the `/sources`. folder into your project (make sure "Copy items if needed" is checked)
3. Rename the "sources" group to `Backtrace` if you'd like.


# Documentation  <a name="documentation"></a>

## Register with Backtrace credentials<a name="documentation-initialization"></a>

- Swift
```swift
Backtrace.register(endpoint: "backtraceEndpoint",
                     token: "backtraceToken")
```
- Objective-C
```objective-c
[Backtrace registerWithEndpoint: @"backtraceEndpoint"
                         andToken: @"backtraceToken"];
```

For more configuration options use `BacktraceConfig` class:

- Swift
```swift
let config = BacktraceConfig(reportPerMin: 3,
                               clientAttributes: ["attribute_name": "attribute_value"])
Backtrace.config(config)
```
- Objective-C
```objective-c
  BacktraceConfig *config = [[BacktraceConfig alloc]
     initWithReportPerMin: 3
      andClientAttributes: @{@"attribute_name": @"attribute_value"}];
  [Backtrace setConfig: config];
```

#### Database initialization <a name="documentation-database-initialization"></a>

`Backtrace` allows you to customize the initialization of `BacktraceDatabase` for local storage of error reports by supplying a `BacktraceDatabaseSettings` parameter, as follows:
- Swift
```swift
let dbSettings = BacktraceDatabaseSettings(dbUrl : "dbUrl",
                                             retryBehaviour = .interval,
                                             mode: .autoSend)
Backtrace.dbSettings(settings)
```
- Objective-C
```objective-c
BacktraceDatabaseSettings *dbSettings = [[BacktraceDatabaseSettings alloc]
       initWithDbUrl: @"dbUrl"
  andRetryBehaviour: BacktraceDbRetryBehaviourInterval
            andMode: BacktraceDbSendModeAuto];
[Backtrace setDbSettings: dbSettings];
```


#### TLS/SSL Support

TLS/SSL support is enabled by default. In case of iOS HTTP request will be rejected.
<b>Not recommended </b> workaround might be obtained by adding:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>example.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```
into `Info.plist` file.

## Sending an error report <a name="documentation-sending-report"></a>
`Backtrace` will send an error/exception report using method:

```swift
@param: error error wrapped into error report being sent to the specified Backtrace endpoint
@param queue queue on which the method will be dispatched
@param async flag indicating whether an error report should be sent asynchronously or not
@param attributes custom attributes attached to the error report
@param attachmentPaths array of attachment paths to be sendException

send(_ error: Error, queue: DispatchQueue = DispatchQueue.global(label: "backtrace.queue", qos: .background), async: Bool = true, attributes: [String: Any]? = nil, attachmentPaths: [String] = [])```
which has only one required parameter `error`.

Objective-C exposes the same API as Swift.

Example in Swift:
```swift
try {
  // throw exception here
}
catch {
    BacktraceClient.send(error,
                         queue: DispatchQueue.main,
                         async: false,
                         attributes: ["attribute_name":"attribute_value"],
                         attachmentPaths: ["first_attachment_path", "second_attachment_path"])
}
```

## Delegates <a name="documentation-events"></a>
Delegates are a design pattern that allows one object to send messages to another object when a specific event happens. `Backtrace` will allow you to handle events `BacktraceDelegate`:

- Swift
  - `onSend(_ error: Error)`
  - `afterSend(_ error: Error, succeeded: Bool)`
  - `onReportStart(_ report: Report)`
  - `onClientLimitReached()`
  - `onUnhandledApplicationException(_ exception: Exception)`
  - `onServerResponse(result: Result<Response, Error>)`

- Objective-C
  - `onSendError:(NSError *) error`
  - `onSendException:(NSException *) exception`
  - `afterSendError:(NSError *) error withSuccess: (bool) succeeded`
  - `onReportStartWithReport:(Report *) report`
  - `onClientLimitReached`
  - `onUnhandledApplicationException:(NSException *) exception`
  - `onServerResponse: (Response *) response withError: (NSError *) error)`
  - `onSuccessfulServerResponse: (Response *) response`
  - `onErrorServerResponse: (NSError *) error`

When your class conforms to the `BacktraceDelegate` you're free to handle all the events.

## Reporting unhandled application exceptions
`Backtrace` also supports reporting of unhandled application exceptions not captured by your do-catch/try-catch blocks. Reporting unhandled exceptions is turned of by default.
To disable this functionality set `handleUnhandledExceptions` to `false`:
- Swift
```swift
Backtrace.handleUnhandledExceptions = false;
```
- Objective-C
```objective-c
[Backtrace setHandleUnhandledExceptions: NO];
```

## Custom client and report classes <a name="documentation-customization"></a>

`BacktraceClient` is an `open public class` and conforms to the protocol `BacktraceClientType`, so you have two options:
 - create `CustomBacktraceClient` which inherits from `BacktraceClient`
 - create `CustomBacktraceClient` which conforms to `BacktraceClientType` and does not rely on `BacktraceClient`

 The second example is recommended only for advanced users or users with certain requirements.

# Architecture  <a name="architecture"></a>

The library is written in pure Swift and does not rely on the Objective-C runtime. That feature makes it extendible for Linux platform. From the other hand Objective-C is fully supported as Swift codebase can be automatically exposed just by adding annotations:

```swift
// pure swift class - does not work with Objective-C
class PureSwiftClass {

}

// swift class which can be exposed to Objective-C
@objc class SwiftClass: NSObject {

}
```

As Swift is meant to be open-source and platform independent the library relies on `protocols` which allows to provide default implementation but simultaneously gives you a lot of place for customization.
