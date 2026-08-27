// Stable C ABI used by the Backtrace Unity macOS native client.

#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>

#ifndef PLCRASHREPORTER_PREFIX
#define PLCRASHREPORTER_PREFIX BTUnity
#endif

#if __has_include(<BTUnityCrashReporter/BTUnityCrashReporter.h>)
#import <BTUnityCrashReporter/BTUnityCrashReporter.h>
#elif __has_include("BTUnityCrashReporter.h")
#import "BTUnityCrashReporter.h"
#else
#error "The Unity bundle target requires the private BTUnityCrashReporter module"
#endif

#if __has_include(<Backtrace/Backtrace-Swift.h>)
#import <Backtrace/Backtrace-Swift.h>
#else
#import "Backtrace-Swift.h"
#endif

// `shutdownForNativeBridge` is an Objective-C runtime entry point intentionally kept out of
// Backtrace Cocoa's public Swift API. Release generated headers omit internal Swift declarations,
// so the private Unity bridge declares the selector it alone is allowed to call.
@interface BacktraceClient (BacktraceUnityBridgeLifecycle)
- (void)shutdownForNativeBridge;
@end

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

#define BT_EXPORT extern "C" __attribute__((visibility("default")))

typedef struct {
    const char *Key;
    const char *Value;
} Entry;

typedef NS_ENUM(int32_t, BTUnityInitializationResult) {
    BTUnityInitializationResultSuccess = 0,
    BTUnityInitializationResultAlreadyInitialized = 1,
    BTUnityInitializationResultInvalidArguments = 2,
    BTUnityInitializationResultStorageInitializationFailed = 3,
    BTUnityInitializationResultInvalidSubmissionUrl = 4,
    BTUnityInitializationResultClientInitializationFailed = 5,
    BTUnityInitializationResultUnexpectedFailure = 6,
};

@interface BTUnityRuntimeState : NSObject

@property(nonatomic, strong, readonly) BacktraceClient *client;
@property(nonatomic, strong, readonly) BacktraceCrashReporter *crashReporter;

- (instancetype)initWithClient:(BacktraceClient *)client
                 crashReporter:(BacktraceCrashReporter *)crashReporter;

@end

@implementation BTUnityRuntimeState

- (instancetype)initWithClient:(BacktraceClient *)client
                 crashReporter:(BacktraceCrashReporter *)crashReporter {
    self = [super init];
    if (self != nil) {
        _client = client;
        _crashReporter = crashReporter;
    }
    return self;
}

@end

// PLCrashReporter does not provide an API to uninstall its process-wide fatal handler. Keep
// the client, reporter, and callback context alive until process exit even after managed code
// calls Disable(). A later Start must remain already-initialized rather than installing a
// second reporter over process-global state.
static BTUnityRuntimeState *BTUnityRuntime = nil;
static NSMutableArray<BacktraceCrashReporter *> *BTUnityCrashReporterOwners = nil;
static BacktraceLogLevel BTUnityConfiguredLogLevel = BacktraceLogLevelWarning;
static BOOL BTUnityManagedInterfaceEnabled = NO;
static BOOL BTUnityHandlerInstallationAttempted = NO;

// Keep this literal in the final binary. The artifact validator uses it as a storage-contract marker,
// all compatibility entry points derive their PLCrashReporter base path from the same versioned relative path.
static NSString *const BTUnityCrashStorageRelativePath = @"Backtrace/NativeCrash/v1/plcrash";
static NSString *const BTUnityLegacyIdentifierPrefix = @"io.backtrace.unity.legacy.";
static NSString *const BTUnityStorageErrorDomain = @"io.backtrace.unity.macos.storage";
static NSString *const BTUnityExceptionContractMarker =
    @"BacktraceUnityExceptionContract:all-c-exports-contained-v1";
static const char BTUnityLifecycleContractMarker[] __attribute__((used, retain)) =
    "BacktraceUnityLifecycleContract:process-lifetime-handler-v1";
static const char BTUnityLoggingContractMarker[] __attribute__((used, retain)) =
    "BacktraceUnityLoggingContract:warning-default-explicit-setter-silent-none-v2";

static BOOL BTShouldLog(BacktraceLogLevel messageLevel) {
    @synchronized([BacktraceClient class]) {
        return BTUnityConfiguredLogLevel != BacktraceLogLevelNone &&
            BTUnityConfiguredLogLevel <= messageLevel;
    }
}

static void BTLogBridgeMessage(BacktraceLogLevel level, NSString *message) {
    if (!BTShouldLog(level)) {
        return;
    }
    NSLog(@"[Backtrace] %@", message ?: @"");
}

static void BTLogCaughtException(const char *operation, NSException *exception) {
    if (!BTShouldLog(BacktraceLogLevelError)) {
        return;
    }
    @try {
        NSLog(@"[Backtrace] %@ caught an exception in %s: %@",
              BTUnityExceptionContractMarker,
              operation,
              exception.name ?: @"NSException");
    } @catch (NSException *loggingException) {
        (void)loggingException;
        if (BTShouldLog(BacktraceLogLevelError)) {
            fprintf(stderr, "[Backtrace] native bridge caught an exception in %s\n", operation);
        }
    }
}

static NSString *BTString(const char *value) {
    if (value == NULL) {
        return @"";
    }
    NSString *result = [NSString stringWithUTF8String:value];
    return result ?: @"";
}

static char *BTDuplicateString(NSString *value) {
    const char *source = (value ?: @"").UTF8String;
    if (source == NULL) {
        source = "";
    }
    const size_t size = strlen(source) + 1;
    char *copy = static_cast<char *>(malloc(size));
    if (copy != NULL) {
        memcpy(copy, source, size);
    }
    return copy;
}

static BOOL BTDebuggerAttached(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    if (sysctl(mib, 4, &info, &size, NULL, 0) == -1) {
        return NO;
    }
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

static BOOL BTValidSubmissionUrl(NSString *rawUrl, NSURL **urlOut) {
    if (rawUrl.length == 0) {
        return NO;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:rawUrl];
    NSString *scheme = components.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) ||
        components.host.length == 0) {
        return NO;
    }
    NSURL *url = components.URL;
    if (url == nil) {
        return NO;
    }
    if (urlOut != NULL) {
        *urlOut = url;
    }
    return YES;
}

static NSError *BTStorageError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:BTUnityStorageErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL BTValidBundleIdentifier(NSString *value) {
    if (value.length == 0 || value.length > 255) {
        return NO;
    }

    NSCharacterSet *asciiAlphanumeric = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"];
    for (NSString *component in [value componentsSeparatedByString:@"."]) {
        if (component.length == 0 ||
            ![asciiAlphanumeric characterIsMember:[component characterAtIndex:0]] ||
            ![asciiAlphanumeric characterIsMember:[component characterAtIndex:component.length - 1]]) {
            return NO;
        }
        for (NSUInteger index = 1; index + 1 < component.length; ++index) {
            const unichar character = [component characterAtIndex:index];
            if (character != '-' && ![asciiAlphanumeric characterIsMember:character]) {
                return NO;
            }
        }
    }
    return YES;
}

static NSString *BTSHA256Hex(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return nil;
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

static NSString *BTLegacyStorageIdentifier(NSError **errorOut) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (BTValidBundleIdentifier(bundleIdentifier)) {
        return bundleIdentifier;
    }

    NSURL *identityURL = NSBundle.mainBundle.bundleURL;
    if (!identityURL.isFileURL || identityURL.path.length == 0) {
        identityURL = NSBundle.mainBundle.executableURL;
    }
    NSString *identityPath = identityURL.isFileURL
        ? identityURL.URLByResolvingSymlinksInPath.URLByStandardizingPath.path
        : nil;
    NSString *digest = identityPath.length == 0 ? nil : BTSHA256Hex(identityPath);
    if (digest.length == 0) {
        if (errorOut != NULL) {
            *errorOut = BTStorageError(
                1,
                @"The application has no valid bundle identifier or stable executable path.");
        }
        return nil;
    }

    NSString *fallback = [BTUnityLegacyIdentifierPrefix stringByAppendingString:digest];
    if (!BTValidBundleIdentifier(fallback)) {
        if (errorOut != NULL) {
            *errorOut = BTStorageError(2, @"Unable to derive a safe application storage identifier.");
        }
        return nil;
    }
    BTLogBridgeMessage(
        BacktraceLogLevelWarning,
        @"native crash storage is using a per-application fallback identifier because the main bundle identifier is missing or invalid.");
    return fallback;
}

static NSString *BTLegacyCrashReportBasePath(NSError **errorOut) {
    NSString *identifier = BTLegacyStorageIdentifier(errorOut);
    if (identifier == nil) {
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *cachesURL = [fileManager URLForDirectory:NSCachesDirectory
                                          inDomain:NSUserDomainMask
                                 appropriateForURL:nil
                                            create:YES
                                             error:errorOut];
    if (cachesURL == nil || !cachesURL.isFileURL) {
        if (cachesURL != nil && errorOut != NULL) {
            *errorOut = BTStorageError(3, @"The user caches directory is not a file URL.");
        }
        return nil;
    }

    NSURL *baseURL = [cachesURL URLByAppendingPathComponent:identifier isDirectory:YES];
    baseURL = [baseURL URLByAppendingPathComponent:BTUnityCrashStorageRelativePath
                                       isDirectory:YES];
    return baseURL.URLByStandardizingPath.path;
}

static NSString *BTPrepareCrashReportBasePath(NSString *rawPath, NSError **errorOut) {
    NSString *path = [rawPath stringByExpandingTildeInPath].stringByStandardizingPath;
    if (path.length == 0 || !path.isAbsolutePath) {
        if (errorOut != NULL) {
            *errorOut = BTStorageError(4, @"The PLCrashReporter base path must be absolute.");
        }
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if ([fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
        if (!isDirectory) {
            if (errorOut != NULL) {
                *errorOut = BTStorageError(5, @"The PLCrashReporter base path is not a directory.");
            }
            return nil;
        }
    } else if (![fileManager createDirectoryAtPath:path
                       withIntermediateDirectories:YES
                                        attributes:nil
                                             error:errorOut]) {
        return nil;
    }

    if (![fileManager isWritableFileAtPath:path]) {
        if (errorOut != NULL) {
            *errorOut = BTStorageError(6, @"The PLCrashReporter base path is not writable.");
        }
        return nil;
    }
    return path;
}

static const char *BTInitializationResultName(BTUnityInitializationResult result) {
    switch (result) {
        case BTUnityInitializationResultSuccess:
            return "success";
        case BTUnityInitializationResultAlreadyInitialized:
            return "alreadyInitialized";
        case BTUnityInitializationResultInvalidArguments:
            return "invalidArguments";
        case BTUnityInitializationResultStorageInitializationFailed:
            return "storageInitializationFailed";
        case BTUnityInitializationResultInvalidSubmissionUrl:
            return "invalidSubmissionUrl";
        case BTUnityInitializationResultClientInitializationFailed:
            return "clientInitializationFailed";
        case BTUnityInitializationResultUnexpectedFailure:
            return "unexpectedFailure";
    }
    return "unknown";
}

static void BTLogInitializationResult(BTUnityInitializationResult result, NSString *detail) {
    const BacktraceLogLevel level = result == BTUnityInitializationResultSuccess
        ? BacktraceLogLevelInfo
        : (result == BTUnityInitializationResultAlreadyInitialized
            ? BacktraceLogLevelWarning
            : BacktraceLogLevelError);
    NSString *message = nil;
    if (detail.length > 0) {
        message = [NSString stringWithFormat:@"native initialization %s: %@",
                   BTInitializationResultName(result), detail];
    } else {
        message = [NSString stringWithFormat:@"native initialization %s",
                   BTInitializationResultName(result)];
    }
    BTLogBridgeMessage(level, message);
}

static BOOL BTValidLogLevel(int32_t rawLevel) {
    return rawLevel >= BacktraceLogLevelDebug && rawLevel <= BacktraceLogLevelNone;
}

static NSSet<BacktraceBaseDestination *> *BTLoggingDestinations(BacktraceLogLevel level) {
    if (level == BacktraceLogLevelNone) {
        return [NSSet set];
    }
    BacktraceConsoleDestination *console =
        [[BacktraceConsoleDestination alloc] initWithLevel:level];
    return [NSSet setWithObject:console];
}

static void BTApplyConfiguredLogging(BacktraceClientConfiguration *configuration) {
    (void)BTUnityLoggingContractMarker;
    configuration.loggingDestinations = BTLoggingDestinations(BTUnityConfiguredLogLevel);
}

static BacktraceClient *BTActiveUnityClient(void) {
    @synchronized([BacktraceClient class]) {
        return BTUnityManagedInterfaceEnabled ? BTUnityRuntime.client : nil;
    }
}

static void BTRecordHandlerInstallationState(BacktraceCrashReporter *crashReporter) {
    if (crashReporter == nil) {
        return;
    }
    if (crashReporter.handlerInstallationAttempted) {
        BTUnityHandlerInstallationAttempted = YES;
        return;
    }

    // Initialization failed before PLCrashReporter enable was entered, so there is no
    // process-wide callback to retain and a later Start may safely retry.
    [BTUnityCrashReporterOwners removeObjectIdenticalTo:crashReporter];
}

static NSMutableDictionary<NSString *, NSString *> *BTBuildAttributes(
    const char *attributeKeys[],
    const char *attributeValues[],
    int32_t attributeCount) {
    NSMutableDictionary<NSString *, NSString *> *attributes =
        [NSMutableDictionary dictionaryWithCapacity:static_cast<NSUInteger>(attributeCount)];
    for (int32_t index = 0; index < attributeCount; ++index) {
        const char *rawKey = attributeKeys[index];
        if (rawKey == NULL) {
            continue;
        }
        NSString *key = BTString(rawKey);
        if (key.length == 0) {
            continue;
        }
        attributes[key] = BTString(attributeValues[index]);
    }
    return attributes;
}

static NSMutableArray<NSURL *> *BTBuildAttachments(
    const char *attachments[],
    int32_t attachmentCount) {
    NSMutableArray<NSURL *> *urls =
        [NSMutableArray arrayWithCapacity:static_cast<NSUInteger>(attachmentCount)];
    for (int32_t index = 0; index < attachmentCount; ++index) {
        const char *rawPath = attachments[index];
        if (rawPath == NULL || rawPath[0] == '\0') {
            continue;
        }
        [urls addObject:[NSURL fileURLWithPath:BTString(rawPath)]];
    }
    return urls;
}

static BOOL BTValidArrayArguments(const char *attributeKeys[],
                                  const char *attributeValues[],
                                  int32_t attributeCount,
                                  const char *attachments[],
                                  int32_t attachmentCount) {
    if (attributeCount < 0 || attachmentCount < 0) {
        return NO;
    }
    if (attributeCount > 0 && (attributeKeys == NULL || attributeValues == NULL)) {
        return NO;
    }
    if (attachmentCount > 0 && attachments == NULL) {
        return NO;
    }
    return YES;
}

static BTUnityInitializationResult BTStartIntegration(
    const char *submissionUrl,
    const char *attributeKeys[],
    const char *attributeValues[],
    int32_t attributeCount,
    bool enableOom,
    const char *attachments[],
    int32_t attachmentCount,
    bool enableClientSideUnwinding,
    int32_t reportsPerMinute,
    NSString *crashReportBasePath) {
    @try {
        @autoreleasepool {
            @synchronized([BacktraceClient class]) {
            (void)BTUnityLifecycleContractMarker;
            if (BTUnityRuntime != nil ||
                BTUnityHandlerInstallationAttempted ||
                BacktraceClient.shared != nil) {
                BTLogInitializationResult(BTUnityInitializationResultAlreadyInitialized, nil);
                return BTUnityInitializationResultAlreadyInitialized;
            }

            if (submissionUrl == NULL || reportsPerMinute < 0 ||
                !BTValidArrayArguments(attributeKeys,
                                       attributeValues,
                                       attributeCount,
                                       attachments,
                                       attachmentCount) ||
                crashReportBasePath.length == 0) {
                BTLogInitializationResult(BTUnityInitializationResultInvalidArguments,
                                          @"One or more native initialization arguments are invalid.");
                return BTUnityInitializationResultInvalidArguments;
            }

            NSURL *url = nil;
            if (!BTValidSubmissionUrl(BTString(submissionUrl), &url)) {
                BTLogInitializationResult(BTUnityInitializationResultInvalidSubmissionUrl,
                                          @"The submission URL must be an absolute HTTP(S) URL.");
                return BTUnityInitializationResultInvalidSubmissionUrl;
            }

            NSError *storageError = nil;
            NSString *reportBasePath = BTPrepareCrashReportBasePath(crashReportBasePath, &storageError);
            if (reportBasePath == nil) {
                BTLogInitializationResult(BTUnityInitializationResultStorageInitializationFailed,
                                          @"Unable to prepare isolated native crash storage.");
                return BTUnityInitializationResultStorageInitializationFailed;
            }

            BacktraceCrashReporter *crashReporter = nil;
            @try {
                const PLCrashReporterSymbolicationStrategy strategy = enableClientSideUnwinding
                    ? PLCrashReporterSymbolicationStrategyAll
                    : PLCrashReporterSymbolicationStrategyNone;
                PLCrashReporterConfig *crashConfig = [[PLCrashReporterConfig alloc]
                    initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeBSD
                    symbolicationStrategy:strategy
                    basePath:reportBasePath];
                if (crashConfig == nil) {
                    BTLogInitializationResult(BTUnityInitializationResultStorageInitializationFailed,
                                              @"PLCrashReporter rejected its configuration.");
                    return BTUnityInitializationResultStorageInitializationFailed;
                }

                crashReporter = [[BacktraceCrashReporter alloc] initWithConfig:crashConfig];
                if (crashReporter == nil) {
                    BTLogInitializationResult(BTUnityInitializationResultStorageInitializationFailed,
                                              @"Backtrace could not create the crash reporter wrapper.");
                    return BTUnityInitializationResultStorageInitializationFailed;
                }

                // Retain every reporter handed to BacktraceClient before initialization can
                // attempt process-wide handler registration. This also keeps a callback owner
                // alive if PLCrashReporter partially registers signals and then reports an
                // initialization failure.
                if (BTUnityCrashReporterOwners == nil) {
                    BTUnityCrashReporterOwners = [NSMutableArray array];
                }
                [BTUnityCrashReporterOwners addObject:crashReporter];

                BacktraceCredentials *credentials =
                    [[BacktraceCredentials alloc] initWithSubmissionUrl:url];
                BacktraceClientConfiguration *configuration =
                    [[BacktraceClientConfiguration alloc]
                        initWithCredentials:credentials
                        dbSettings:[BacktraceDatabaseSettings new]
                        reportsPerMin:static_cast<NSInteger>(reportsPerMinute)
                        allowsAttachingDebugger:NO
                        oomMode:(enableOom ? BacktraceOomModeFull : BacktraceOomModeNone)];

                BTApplyConfiguredLogging(configuration);

                NSError *clientError = nil;
                BacktraceClient *client = [[BacktraceClient alloc]
                    initWithConfiguration:configuration
                    crashReporter:crashReporter
                    error:&clientError];
                BTRecordHandlerInstallationState(crashReporter);
                if (client == nil || clientError != nil) {
                    BTLogInitializationResult(
                        BTUnityInitializationResultClientInitializationFailed,
                        @"BacktraceClient initialization failed. See Cocoa diagnostics for the error category.");
                    return BTUnityInitializationResultClientInitializationFailed;
                }

                client.attributes = BTBuildAttributes(attributeKeys, attributeValues, attributeCount);
                client.attachments = BTBuildAttachments(attachments, attachmentCount);

                // Publish process-lifetime state only after every fallible initialization step
                // succeeds. The runtime must outlive Disable() because PLCrashReporter cannot
                // unregister the fatal handler or its unretained callback context.
                BTUnityRuntime = [[BTUnityRuntimeState alloc] initWithClient:client
                                                               crashReporter:crashReporter];
                BTUnityManagedInterfaceEnabled = YES;
                BacktraceClient.shared = client;
                BTLogInitializationResult(BTUnityInitializationResultSuccess, nil);
                return BTUnityInitializationResultSuccess;
            } @catch (NSException *exception) {
                BTRecordHandlerInstallationState(crashReporter);
                BTLogCaughtException("BTStartIntegration.configuration", exception);
                return BTUnityInitializationResultUnexpectedFailure;
            }
            }
        }
    } @catch (NSException *exception) {
        BTLogCaughtException("BTStartIntegration", exception);
        return BTUnityInitializationResultUnexpectedFailure;
    }
}

static void BTFreeAttributeEntries(Entry *entries, int32_t size) {
    if (entries == NULL) {
        return;
    }
    const int32_t count = size > 0 ? size : 0;
    for (int32_t index = 0; index < count; ++index) {
        free(const_cast<char *>(entries[index].Key));
        free(const_cast<char *>(entries[index].Value));
    }
    free(entries);
}

BT_EXPORT int32_t BacktraceUnityBridgeVersion(void) {
    @try {
        return 3;
    } @catch (NSException *exception) {
        BTLogCaughtException("BacktraceUnityBridgeVersion", exception);
        return 0;
    }
}

BT_EXPORT int32_t SetBacktraceLogLevel(int32_t rawLevel) {
    @try {
        @autoreleasepool {
            @synchronized([BacktraceClient class]) {
                if (!BTValidLogLevel(rawLevel)) {
                    return BTUnityInitializationResultInvalidArguments;
                }

                BTUnityConfiguredLogLevel = static_cast<BacktraceLogLevel>(rawLevel);
                NSSet<BacktraceBaseDestination *> *destinations =
                    BTLoggingDestinations(BTUnityConfiguredLogLevel);
                [BacktraceLogger setDestinations:destinations];
                if (BTUnityRuntime != nil) {
                    BTUnityRuntime.client.loggingDestinations = destinations;
                }
                return BTUnityInitializationResultSuccess;
            }
        }
    } @catch (NSException *exception) {
        BTLogCaughtException("SetBacktraceLogLevel", exception);
        return BTUnityInitializationResultUnexpectedFailure;
    }
}

BT_EXPORT int32_t StartBacktraceIntegrationV3(
    const char *submissionUrl,
    const char *attributeKeys[],
    const char *attributeValues[],
    int32_t attributeCount,
    bool enableOom,
    const char *attachments[],
    int32_t attachmentCount,
    bool enableClientSideUnwinding,
    int32_t reportsPerMinute,
    const char *crashReportBasePath) {
    @try {
        @autoreleasepool {
            return BTStartIntegration(submissionUrl,
                                      attributeKeys,
                                      attributeValues,
                                      attributeCount,
                                      enableOom,
                                      attachments,
                                      attachmentCount,
                                      enableClientSideUnwinding,
                                      reportsPerMinute,
                                      crashReportBasePath == NULL
                                          ? nil
                                          : BTString(crashReportBasePath));
        }
    } @catch (NSException *exception) {
        BTLogCaughtException("StartBacktraceIntegrationV3", exception);
        return BTUnityInitializationResultUnexpectedFailure;
    }
}

BT_EXPORT int32_t StartBacktraceIntegrationV2(
    const char *submissionUrl,
    const char *attributeKeys[],
    const char *attributeValues[],
    int32_t attributeCount,
    bool enableOom,
    const char *attachments[],
    int32_t attachmentCount,
    bool enableClientSideUnwinding,
    int32_t reportsPerMinute) {
    @try {
        @autoreleasepool {
            NSError *storageError = nil;
            NSString *basePath = BTLegacyCrashReportBasePath(&storageError);
            if (basePath == nil) {
                BTLogInitializationResult(BTUnityInitializationResultStorageInitializationFailed,
                                          @"Unable to derive isolated native crash storage.");
                return BTUnityInitializationResultStorageInitializationFailed;
            }
            return BTStartIntegration(submissionUrl,
                                      attributeKeys,
                                      attributeValues,
                                      attributeCount,
                                      enableOom,
                                      attachments,
                                      attachmentCount,
                                      enableClientSideUnwinding,
                                      reportsPerMinute,
                                      basePath);
        }
    } @catch (NSException *exception) {
        BTLogCaughtException("StartBacktraceIntegrationV2", exception);
        return BTUnityInitializationResultUnexpectedFailure;
    }
}

BT_EXPORT void StartBacktraceIntegration(
    const char *submissionUrl,
    const char *attributeKeys[],
    const char *attributeValues[],
    int32_t attributeCount,
    bool enableOom,
    const char *attachments[],
    int32_t attachmentCount,
    bool enableClientSideUnwinding) {
    @try {
        @autoreleasepool {
            NSError *storageError = nil;
            NSString *basePath = BTLegacyCrashReportBasePath(&storageError);
            if (basePath == nil) {
                BTLogInitializationResult(BTUnityInitializationResultStorageInitializationFailed,
                                          @"Unable to derive isolated native crash storage.");
                return;
            }
            (void)BTStartIntegration(submissionUrl,
                                     attributeKeys,
                                     attributeValues,
                                     attributeCount,
                                     enableOom,
                                     attachments,
                                     attachmentCount,
                                     enableClientSideUnwinding,
                                     30,
                                     basePath);
        }
    } @catch (NSException *exception) {
        BTLogCaughtException("StartBacktraceIntegration", exception);
    }
}

BT_EXPORT void GetAttributes(Entry **entriesOut, int32_t *sizeOut) {
    Entry *entries = NULL;
    int32_t count = 0;
    @try {
        @autoreleasepool {
            if (entriesOut != NULL) {
                *entriesOut = NULL;
            }
            if (sizeOut != NULL) {
                *sizeOut = 0;
            }
            if (entriesOut == NULL || sizeOut == NULL) {
                return;
            }

            BacktraceClient *client = BTActiveUnityClient();
            NSDictionary<NSString *, NSString *> *attributes =
                client == nil ? @{} : client.attributes;
            NSArray<NSString *> *keys =
                [attributes.allKeys sortedArrayUsingSelector:@selector(compare:)];
            if (keys.count == 0 || keys.count > INT32_MAX) {
                return;
            }

            count = static_cast<int32_t>(keys.count);
            entries = static_cast<Entry *>(calloc(static_cast<size_t>(count), sizeof(Entry)));
            if (entries == NULL) {
                return;
            }

            for (int32_t index = 0; index < count; ++index) {
                NSString *key = keys[static_cast<NSUInteger>(index)];
                NSString *value = [NSString stringWithFormat:@"%@", attributes[key] ?: @""];
                entries[index].Key = BTDuplicateString(key);
                entries[index].Value = BTDuplicateString(value);
                if (entries[index].Key == NULL || entries[index].Value == NULL) {
                    BTFreeAttributeEntries(entries, count);
                    entries = NULL;
                    return;
                }
            }

            *entriesOut = entries;
            *sizeOut = count;
            entries = NULL; // Ownership transfers to the managed caller.
        }
    } @catch (NSException *exception) {
        BTFreeAttributeEntries(entries, count);
        if (entriesOut != NULL) {
            *entriesOut = NULL;
        }
        if (sizeOut != NULL) {
            *sizeOut = 0;
        }
        BTLogCaughtException("GetAttributes", exception);
    }
}

BT_EXPORT void FreeAttributes(Entry *entries, int32_t size) {
    @try {
        BTFreeAttributeEntries(entries, size);
    } @catch (NSException *exception) {
        BTLogCaughtException("FreeAttributes", exception);
    }
}

BT_EXPORT void NativeReport(const char *message,
                            bool setMainThreadAsFaultingThread,
                            bool ignoreIfDebugger) {
    @try {
        @autoreleasepool {
            (void)setMainThreadAsFaultingThread;
            BacktraceClient *client = BTActiveUnityClient();
            if (client == nil ||
                (ignoreIfDebugger && BTDebuggerAttached())) {
                return;
            }
            [client sendWithMessage:BTString(message)
                    attachmentPaths:@[]
                         completion:^(__unused BacktraceResult *result) {}];
        }
    } @catch (NSException *exception) {
        BTLogCaughtException("NativeReport", exception);
    }
}

BT_EXPORT void AddAttribute(const char *key, const char *value) {
    @try {
        @autoreleasepool {
            BacktraceClient *client = BTActiveUnityClient();
            if (client == nil || key == NULL) {
                return;
            }
            NSString *attributeKey = BTString(key);
            if (attributeKey.length == 0) {
                return;
            }
            NSMutableDictionary<NSString *, NSString *> *attributes =
                [client.attributes mutableCopy] ?: [NSMutableDictionary dictionary];
            attributes[attributeKey] = BTString(value);
            client.attributes = attributes;
        }
    } @catch (NSException *exception) {
        BTLogCaughtException("AddAttribute", exception);
    }
}

BT_EXPORT const char *BtCrash(void) {
    @try {
        return "ok";
    } @catch (NSException *exception) {
        BTLogCaughtException("BtCrash", exception);
        return "error";
    }
}

BT_EXPORT void Disable(void) {
    @try {
        @autoreleasepool {
            BacktraceClient *client = nil;
            @synchronized([BacktraceClient class]) {
                // Atomically detach managed operations, but do not wait on Cocoa queues while
                // holding the class monitor. A transport can be stalled indefinitely.
                BTUnityManagedInterfaceEnabled = NO;
                client = BTUnityRuntime.client;
                if (BTUnityRuntime != nil &&
                    BacktraceClient.shared == BTUnityRuntime.client) {
                    BacktraceClient.shared = nil;
                }
            }

            // Stop non-fatal Cocoa activity outside the bridge monitor. The process-wide
            // PLCrashReporter handler and callback owner intentionally remain alive because
            // PLCrashReporter has no safe uninstall operation.
            [client shutdownForNativeBridge];
        }
    } @catch (NSException *exception) {
        BTLogCaughtException("Disable", exception);
    }
}
