# Backtrace

[Backtrace](http://backtrace.io/)'s integration with iOS, macOS and tvOS applications allows customers to capture and report handled and unhandled exceptions to their Backtrace instance, instantly offering the ability to prioritise and debug software errors.

<p align="center">
    <img src="https://img.shields.io/badge/platform-iOS%2010%2B%20%7C%20tvOS%2010%2B%20%7C%20macOS%2010.10%2B-blue.svg" alt="Supported platforms"/>
    <a href="https://masterer.apple.com/swift"><img src="https://img.shields.io/badge/language-swift%204%20%7C%20objective--c-brigthgreen.svg" alt="Supported languages" /></a>
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

    return YES;
}

@end
```

# Table of contents
1. [Features Summary](#features-summary)
2. [Installation](#installation)
    * [Cocoapods](#installation-cocoapods)
3. [Documentation](#documentation)
    1. [Initialize client](#documentation-client-initialization)
    2. [Configure client](#documentation-client-configuration)
        * [Database settings](#documentation-database-settings)
        * [PLCrashReporter configuration](#documentation-plcrashreporter-configuration)
    3. [Events handling](#documentation-events-handling)
    4. [Attributes](#documentation-attributes)
    5. [Attachments](#documentation-attachments)
    6. [Sending reports](#documentation-sending-report)
        1. [Error/NSError](#documentation-sending-error)
        2. [NSException](#documentation-sending-exception)
        3. [macOS note](#documentation-sending-report-macOS)
4. [FAQ](#faq)
    1. [Missing dSYM files](#faq-missing-dsym)
        * [Finding dSYMs while building project](#faq-finding-dsym-building)
        * [Finding dSYMs while archiving project](#faq-finding-dsym-archiving)

# Features Summary <a name="features-summary"></a>
* Light-weight client library written in Swift with full Objective-C support that quickly submits exceptions/errors and crashes to your Backtrace dashboard includes:
  * system metadata,
  * machine metadata,
  * signal metadata,
  * exception metadata,
  * thread metadata,
  * process metadata.
* Supports iOS, macOS and tvOS platforms.
* Swift first protocol-oriented framework.

# Installation <a name="installation"></a>

## via CocoaPods <a name="installation-cocoapods"></a>

To use [CocoaPods](https://cocoapods.org) just add this to your Podfile:

```
pod 'Backtrace'
```

**Note:** It is required to specify `use_frameworks!` in your Podfile.

# Documentation <a name="documentation"></a>

## Initialize Backtrace client <a name="documentation-client-initialization"></a>
Initializing Backtrace client requires registration to Backtrace services. You can register to Backtrace services using provided submission url (see: <a href="https://help.backtrace.io/troubleshooting/what-is-a-submission-url">What is a submission url?</a>) and token (see: <a href="https://help.backtrace.io/troubleshooting/what-is-a-submission-token">What is a submission token?</a>). These credentials you can supply using `BacktraceCredentials`.

- Swift
```swift
let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "https://backtrace.io")!, token: "token")
BacktraceClient.shared = try? BacktraceClient(credentials: backtraceCredentials)
```

- Objective-C
```objective-c
BacktraceCredentials *backtraceCredentials = [[BacktraceCredentials alloc]
                                             initWithEndpoint: [NSURL URLWithString: @"https://backtrace.io"]
                                             token: @"token"];
BacktraceClient.shared = [[BacktraceClient alloc] initWithCredentials: backtraceCredentials error: error];
```

Additionally, the `BacktraceCredentials` object can be initialized using provided URL containing `universe` and `token`:

- Swift
```swift
let backtraceCredentials = BacktraceCredentials(submissionUrl: URL(string: "https://submit.backtrace.io/{universe}/{token}/plcrash")!)
```

- Objective-C
```objective-c
BacktraceCredentials *backtraceCredentials = [[BacktraceCredentials alloc] initWithSubmissionUrl: [NSURL URLWithString: @"https://submit.backtrace.io/{universe}/{token}/plcrash"]];
```

## Configure Backtrace client <a name="documentation-client-configuration"></a>
For more advanced usage of `BacktraceClient`, you can supply `BacktraceClientConfiguration` as a parameter. See the following example:
- Swift
```swift
let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "https://backtrace.io")!, token: "token")
let configuration = BacktraceClientConfiguration(credentials: backtraceCredentials,
                                                 dbSettings: BacktraceDatabaseSettings(),
                                                 reportsPerMin: 10,
                                                 allowsAttachingDebugger: false)
BacktraceClient.shared = try? BacktraceClient(configuration: configuration)
```

- Objective-C
```objective-c
BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                     initWithEndpoint: [NSURL URLWithString: @"https://backtrace.io"]
                                     token: @"token"];

BacktraceClientConfiguration *configuration = [[BacktraceClientConfiguration alloc]
                                               initWithCredentials: credentials
                                               dbSettings: [[BacktraceDatabaseSettings alloc] init]
                                               reportsPerMin: 3
                                               allowsAttachingDebugger: NO];

BacktraceClient.shared = [[BacktraceClient alloc] initWithConfiguration: configuration error: nil];
```

**Note:** Backtrace library will *not* send any reports if the `allowsAttachingDebugger` flag is set to `false`.

### Database settings <a name="documentation-database-settings"></a>
BacktraceClient allows you to customize the initialization of BacktraceDatabase for local storage of error reports by supplying a BacktraceDatabaseSettings parameter, as follows:

- Swift
```swift
let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "https://backtrace.io")!, token: "token")
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

- Objective-C
```objective-c
BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                     initWithEndpoint: [NSURL URLWithString: @"https://backtrace.io"]
                                     token: @"token"];

BacktraceDatabaseSettings *backtraceDatabaseSettings = [[BacktraceDatabaseSettings alloc] init];
backtraceDatabaseSettings.maxRecordCount = 1000;
backtraceDatabaseSettings.maxDatabaseSize = 10;
backtraceDatabaseSettings.retryInterval = 5;
backtraceDatabaseSettings.retryLimit = 3;
backtraceDatabaseSettings.retryBehaviour = RetryBehaviourInterval;
backtraceDatabaseSettings.retryOrder = RetryOderStack;

BacktraceClientConfiguration *configuration = [[BacktraceClientConfiguration alloc]
                                               initWithCredentials: credentials
                                               dbSettings: backtraceDatabaseSettings
                                               reportsPerMin: 3
                                               allowsAttachingDebugger: NO];

BacktraceClient.shared = [[BacktraceClient alloc] initWithConfiguration: configuration error: nil];
```

### PLCrashReporter configuration <a name="documentation-plcrashreporter-configuration"></a>
`BacktraceClient` allows to customize the configuration of the `PLCrashReporter` by injecting its instance.

- Swift
```swift
let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "https://backtrace.io")!, token: "token")
let backtraceConfiguration = BacktraceClientConfiguration(credentials: backtraceCredentials)
BacktraceClient.shared = try? BacktraceClient(
    configuration: backtraceConfiguration,
    crashReporter: BacktraceCrashReporter(config: PLCrashReporterConfig.defaultConfiguration()))
// or 
BacktraceClient.shared = try? BacktraceClient(
    configuration: backtraceConfiguration,
    crashReporter: BacktraceCrashReporter(reporter: PLCrashReporter.shared()))
```

- Objective-C
```objective-c
BacktraceCredentials *credentials = [[BacktraceCredentials alloc]
                                     initWithEndpoint: [NSURL URLWithString: @"https://backtrace.io"]
                                     token: @"token"];

BacktraceClientConfiguration *configuration = [[BacktraceClientConfiguration alloc] 
                                                initWithCredentials: credentials];

BacktraceClient.shared = [[BacktraceClient alloc]
                            initWithConfiguration: configuration
                            crashReporter: [[BacktraceCrashReporter alloc] initWithConfig: PLCrashReporterConfig.defaultConfiguration]
                            error: nil];
    
// or
BacktraceClient.shared = [[BacktraceClient alloc]
                            initWithConfiguration: configuration
                            crashReporter: [[BacktraceCrashReporter alloc] initWithReporter: PLCrashReporter.sharedReporter]
                            error: nil];
```


## Events handling <a name="documentation-events-handling"></a>
`BacktraceClient` allows you to subscribe for events produced before and after sending each report. You have to only attach object which confirm to `BacktraceClientDelegate` protocol.
- Swift
```swift
// assign `self` or any other object as a `BacktraceClientDelegate`
BacktraceClient.shared?.delegate = self

// handle events
func willSend(_ report: BacktraceCrashReport) -> (BacktraceCrashReport)
func willSendRequest(_ request: URLRequest) -> URLRequest
func serverDidFail(_ error: Error)
func serverDidRespond(_ result: BacktraceResult)
func didReachLimit(_ result: BacktraceResult)
```

- Objective-C
```objective-c
// assign `self` or any other object as a `BacktraceClientDelegate`
BacktraceClient.shared.delegate = self;

//handle events
- (BacktraceReport *) willSend: (BacktraceReport *)report;
- (void) serverDidFail: (NSError *)error;
- (void) serverDidRespond: (BacktraceResult *)result;
- (NSURLRequest *) willSendRequest: (NSURLRequest *)request;
- (void) didReachLimit: (BacktraceResult *)result;
```
Attaching `BacktraceClientDelegate` allows you to e.g. modify report before send:
- Swift
```swift
func willSend(_ report: BacktraceReport) -> (BacktraceReport) {
    report.attributes["added"] = "just before send"
    return report
}
```
- Objctive-C
```objective-c
- (BacktraceReport *)willSend:(BacktraceReport *)report {
    NSMutableDictionary *dict = [report.attributes mutableCopy];
    [dict setObject: @"just before send" forKey: @"added"];
    report.attributes = dict;
    return report;
}
```

## Attributes <a name="documentation-attributes"></a>
You can add custom attributes that should be send alongside crash and errors/exceptions:
- Swift
```swift
BacktraceClient.shared?.attributes = ["foo": "bar", "testing": true]
```

- Objective-C
```objective-c
BacktraceClient.shared.attributes = @{@"foo": @"bar", @"testing": YES};
```
Set attributes are attached to each report. You can specify unique set of attributes for specific report in `willSend(_:)` method of `BacktraceClientDelegate`. See [events handling](#documentation-events-handling) for more information.

## Attachments <a name="documentation-attachments"></a>
For each report you can attach files by supplying an array of file paths.
- Swift
```swift
let filePath = Bundle.main.path(forResource: "test", ofType: "txt")!
BacktraceClient.shared?.send(attachmentPaths: [filePath]) { (result) in
    print(result)
}
```
- Objectice-C
```objective-c
NSArray *paths = @[[[NSBundle mainBundle] pathForResource: @"test" ofType: @"txt"]];
[[BacktraceClient shared] sendWithAttachmentPaths:paths completion:^(BacktraceResult * _Nonnull result) {
    NSLog(@"%@", result);
}];
```
Supplied files are attached for each report. You can specify unique set of files for specific report in `willSend(_:)` method of `BacktraceClientDelegate`. See [events handling](#documentation-events-handling) for more information.

## Sending an error report <a name="documentation-sending-report"></a>
Registered `BacktraceClient` will be able to send a crash reports. Error report is automatically generated based.

### Sending `Error/NSError` <a name="documentation-sending-error"></a>
- Swift
```swift
@objc func send(completion: ((BacktraceResult) -> Void))
```
- Objective-C
```objective-c
 - (void) sendWithCompletion: (void (^)(BacktraceResult * _Nonnull)) completion;
```

### Sending `NSException` <a name="documentation-sending-exception"></a>
- Swift
```swift
@objc func send(exception: NSException, completion: ((BacktraceResult) -> Void))
```
- Objective-C
```objective-c
 - (void) sendWithException: NSException completion: (void (^)(BacktraceResult * _Nonnull)) completion;
```

### macOS note <a name="documentation-sending-report-macOS"></a>
If you want to catch additional exceptions on macOS which are not forwarded by macOS runtime, set `NSPrincipalClass` to `Backtrace.BacktraceCrashExceptionApplication` in your `Info.plist`.

Alternatively, you can set:
- Swift
```swift
UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
```
- Objective-C
```objective-c
[[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSApplicationCrashOnExceptions": @YES }];
```
but it crashes your app if you don't use `@try ... @catch`.

# FAQ <a name="faq"></a>
## Missing dSYM files <a name="faq-missing-dsym"></a>
Make sure your project is configured to generate the debug symbols:
* Go to your project target's build settings: `YourTarget -> Build Settings`.
* Search for `Debug Information Format`.
* Select `DWARF with dSYM File`.
![alt text](https://github.com/backtrace-labs/backtrace-cocoa/blob/master/docs/screenshots/xcode-debug-information-format.png)

### Finding dSYMs while building project <a name="faq-finding-dsym-building"></a>
* Build the project.
* Build products and dSYMs are placed into the `Products` directory.
![alt text](https://github.com/backtrace-labs/backtrace-cocoa/blob/master/docs/screenshots/xcode-products.png)
![alt text](https://github.com/backtrace-labs/backtrace-cocoa/blob/master/docs/screenshots/finder-dsyms-products.png)
* Zip all the `dSYM` files and upload to Backtrace services (see: <a href="https://help.backtrace.io/product-guide/symbolification">Symbolification</a>)

### Finding dSYMs while archiving project <a name="faq-finding-dsym-archiving"></a>
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
