# Backtrace

[Backtrace](http://backtrace.io/)'s integration with iOS and macOS applications allows customers to capture and report handled and unhandled exceptions to their Backtrace instance, instantly offering the ability to prioritise and debug software errors.

<p align="center">
    <img src="https://img.shields.io/badge/platform-iOS%2010%2B%20%7C%20macOS%2010.10%2B-blue.svg" alt="Supported platforms"/>
    <a href="https://masterer.apple.com/swift"><img src="https://img.shields.io/badge/language-swift%204-brightgreen.svg" alt="Language: Swift 4" /></a>
    <a href="https://masterer.apple.com/swift"><img src="https://img.shields.io/badge/language-objective--c-brightgreen.svg" alt="Language: Objecive-C" /></a>
    <a href="https://cocoapods.org/pods/Backtrace"><img src="https://img.shields.io/cocoapods/v/Backtrace.svg?style=flat" alt="CocoaPods compatible" /></a>
    <img src="http://img.shields.io/badge/license-MIT-lightgrey.svg?style=flat" alt="License: MIT" />
    <img src="https://travis-ci.org/backtrace-labs/backtrace-cocoa.svg?branch=master"/>
</p>

## Minimal usage

### Create the `BacktraceClient` using `init(credentials:)` initializer and then send error/exception just by calling method `send`:

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
        BacktraceClient.shared = try? BacktraceClient(credentials: backtraceCredentials)

        do {
            try throwingFunc()
        } catch {
            BacktraceClient.shared?.send { (result) in
                print(result)
            }
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
    BacktraceClient.shared = [[BacktraceClient alloc] initWithCredentials: credentials error: nil];

    // sending NSException
    @try {
        NSArray *array = @[];
        NSObject *object = array[1]; // will throw exception
    } @catch (NSException *exception) {
        [[BacktraceClient shared] sendWithException: exception completion:^(BacktraceResult * _Nonnull result) {
            NSLog(@"%@", result);
        }];
    } @finally {

    }

    //sending NSError
    NSError *error = [NSError errorWithDomain: @"backtrace.domain" code: 100 userInfo: @{}];
    [[BacktraceClient shared] sendWithCompletion:^(BacktraceResult * _Nonnull result) {
        NSLog(@"%@", result);
    }];

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
BacktraceClient.shared = try? BacktraceClient(credentials: BacktraceCredentials)
```
- Objective-C
```objective-c
BacktraceClient.shared = [[BacktraceClient alloc] initWithCredentials: BacktraceCredentials error: error];
```

## Backtrace client configuration
For more advanced usage of BacktraceClient, you can supply BacktraceClientConfiguration as a parameter. See the following example:
```swift
let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "https://backtrace.io")!,
                                                        token: "token")
let configuration = BacktraceClientConfiguration(credentials: backtraceCredentials,
                                                 dbSettings: BacktraceDatabaseSettings(),
                                                 reportsPerMin: 10)
BacktraceClient.shared = try? BacktraceClient(configuration: configuration)
```

### Database settings
BacktraceClient allows you to customize the initialization of BacktraceDatabase for local storage of error reports by supplying a BacktraceDatabaseSettings parameter, as follows:
```swift
let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "https://backtrace.io")!,
                                                        token: "token")
let backtraceDatabaseSettings = BacktraceDatabaseSettings()
backtraceDatabaseSettings.maxRecordCount = 1000
backtraceDatabaseSettings.maxDatabaseSize = 10
backtraceDatabaseSettings.retryInterval = 5
backtraceDatabaseSettings.retryLimit = 3
backtraceDatabaseSettings.retryBehaviour = RetryBehaviour.interval
backtraceDatabaseSettings.retryOrder = RetryOder.queue
let backtraceConfiguration = BacktraceClientConfiguration(credentials: backtraceCredentials,
                                                          dbSettings: backtraceDatabaseSettings,
                                                          reportsPerMin: 10)
BacktraceClient.shared = try? BacktraceClient(configuration: backtraceConfiguration)
```

### Events handling
BacktraceClient allows you to subscribe for events produced before and after sending error report:
- Swift
```swift
BacktraceClient.shared?.delegate = self

func willSend(_ report: BacktraceCrashReport) -> (BacktraceCrashReport)
func willSendRequest(_ request: URLRequest) -> URLRequest
func serverDidFail(_ error: Error)
func serverDidResponse(_ result: BacktraceResult)
func didReachLimit(_ result: BacktraceResult)
```

### User attributes
You can add custom user attributes that should be send alongside crash and erros/exceptions:
- Swift
```swift
BacktraceClient.shared?.userAttributes = ["foo": "bar", "testing": true]
```

## Backtrace client configuration
For more advanced usage of BacktraceClient, you can supply BacktraceClientConfiguration as a parameter. See the following example:
```swift
let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "backtrace_endpoint_url")!,
                                                token: "token")
let backtraceConfiguration = BacktraceClientConfiguration(credentials: backtraceCredentials,
                                                          dbSettings: BacktraceDatabaseSettings(),
                                                          reportsPerMin: 10)
BacktraceClient.shared.register(configuration: backtraceConfiguration)
```

### Database settings
BacktraceClient allows you to customize the initialization of BacktraceDatabase for local storage of error reports by supplying a BacktraceDatabaseSettings parameter, as follows:
```swift
let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "backtrace_endpoint_url")!,
                                                token: "token")
let backtraceDatabaseSettings = BacktraceDatabaseSettings()
backtraceDatabaseSettings.maxRecordCount = 1000
backtraceDatabaseSettings.maxDatabaseSize = 10
backtraceDatabaseSettings.retryInterval = 5
backtraceDatabaseSettings.retryLimit = 3
backtraceDatabaseSettings.retryBehaviour = RetryBehaviour.interval
backtraceDatabaseSettings.retryOrder = RetryOder.queue
let backtraceConfiguration = BacktraceClientConfiguration(credentials: backtraceCredentials,
                                                          dbSettings: backtraceDatabaseSettings,
                                                          reportsPerMin: 10)
BacktraceClient.shared.register(configuration: backtraceConfiguration)
```

### Events handling
BacktraceClient allows you to subscribe for events produced before and after sending error report:
- Swift
```swift
func willSend(_ report: BacktraceCrashReport) -> (BacktraceCrashReport)
func willSendRequest(_ request: URLRequest) -> URLRequest
func serverDidFail(_ error: Error)
func serverDidResponse(_ result: BacktraceResult)
func didReachLimit(_ result: BacktraceResult)
```

## Sending an error report <a name="documentation-sending-report"></a>
Registered `BacktraceClient` will be able to send an crash reports. Error report is automatically generated based.

### Sending `Error/NSError`
- Swift
```swift
@objc func send(completion: ((BacktraceResult) -> Void))
```
- Objective-C
```objective-c
 - (void) sendWithCompletion: (void (^)(BacktraceResult * _Nonnull)) completion;
```

### Sending `NSException`
- Swift
```swift
@objc func send(exception: NSException, completion: ((BacktraceResult) -> Void))
```
- Objective-C
```objective-c
 - (void) sendWithException: NSException completion: (void (^)(BacktraceResult * _Nonnull)) completion;
```

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
