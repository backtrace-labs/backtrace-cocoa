# Backtrace Cocoa Release Notes

## Version 2.2.0

This release brings OS 27 scene-lifecycle readiness, more reliable native crash delivery, and improved Unity integration artifacts.

### OS 27 Readiness and Examples

- Prepares the Swift and Objective-C iOS examples and the tvOS example for iOS/iPadOS 27 and tvOS 27 with UIKit scene delegates, scene-owned windows, and scene-based storyboard loading. Backtrace initialization remains once per process at application launch. ([#179](https://github.com/backtrace-labs/backtrace-cocoa/pull/179))
- Raises the repository's iOS/tvOS Xcode targets and workspace deployment targets to 15.0.
- Fixes Objective-C example startup and metrics initialization, and resolves the tvOS configuration initializer ambiguity.

Scene-lifecycle migration applies to the examples. Applications integrating Backtrace must configure their own scenes, updating the SDK does not migrate the host application.

### Native Crash Delivery and Recovery

- Saves pending native crashes durably before removing the original PLCrashReporter files, with duplicate-ingestion protection and automatic migration of existing retry databases to ModelV2.
- Coordinates report ownership across repository instances and processes, atomically loading the claimed report so concurrent updates cannot result in stale payloads or attachment generations being submitted.
- Gives each new pending native crash an initial submission opportunity even with `RetryBehaviour.none`. Initial reports take priority over ordinary retries and remain protected from capacity eviction while awaiting their first attempt, including when delayed by the local rate limit.
- Retains transient transport failures and HTTP 408, 425, 429, and 5xx responses for retry when retries are enabled. Permanent URL/configuration failures and other non-retryable responses are cleaned up instead of retried indefinitely.
- Preserves crash attributes and repository-owned attachment copies, tolerates unavailable optional metadata, and isolates invalid payloads and malformed records so they do not block valid reports.
- Coordinates in-flight submissions during shutdown and releases database connections, process leases, locks, and file descriptors when they are no longer needed.

### Reporting and Diagnostics

- Uses one delegate-aware submission path and thread-safe rate limiter for live reports, pending native crashes, retries, and OOM reports. `reportsPerMin = 0` now means unlimited submissions without accumulating rate-limit timestamps.
- Adds `BacktraceClientConfiguration.loggingDestinations` and `delegate` so applications can capture initialization diagnostics and observe pending-report delivery from startup.

### Unity Native Integrations

- Isolates the Unity macOS plugin's crash storage and uses a private, symbol-prefixed PLCrashReporter 1.12.0 runtime to prevent Unity from consuming Backtrace's pending reports from a shared location.
- Adds `StartBacktraceIntegrationV3` with an explicit crash-storage path and clear initialization results. Native handler ownership lasts for the process lifetime; re-enabling capture after `Disable()` requires a player-process restart.
- Delivers a flat, universal arm64/x86_64 macOS bundle without nested framework symlinks, together with a matching dSYM, database models, privacy metadata, third-party attribution, and checksums.
- Adds a dedicated Unity iOS XCFramework release archive containing device and simulator slices, alongside the standard Cocoa archives. ([#178](https://github.com/backtrace-labs/backtrace-cocoa/pull/178))

## Version 2.1.0
- Adds OSInfo conditional import UIKit & guards UIDevice to unblock non-UIKit builds (#160)
- Updates Target Platforms (#161)
- Updates swift tools version, framework targets & handle tests deprecations (#162)
- Updates OOM handling (#163)
- Bumps PLCrashReporter ver to 1.12.0' (#165)
- Pins workflow runner to macos-14 (#168)

## Version 2.0.9
- Adds OS/build and CPU/architecture metadata, fixes uname fields, and exposes isSimulator attribute (#154)
- Updates submission url documentation links in Example Apps (#156)
- Adds custom .plcrash directory with configurable FileProtectionType and updates example App & Tests (#157)
- Generates live reports on the faulting thread, fixes thread attribution, and defers Mach-port cleanup (#158)

## Version 2.0.8
- Fixes CoreData swift/objc attributes Interoperability (#149)
- Updates Transformer class to use NSSecureUnarchiveFromData secure coding (#150)
- Updates PersistentRepository to safely perform concurrent Core Data operations (#151)
- Fixes doc-comment parameter name mismatch ("level" → "type") (#153)

## Version 2.0.7
- Adds explicit BacktraceResources-Info.plist

## Version 2.0.6
- Distributes XCFramework (#136)
- Adds Mac catalyst support (#139)
- Embeds xcprivacy manifest (#140)
- Codesigns binaries (#141)
- Generates PLCReport with exception (#142)

## Version 2.0.5
- Enables client side unwinding default setting (#134)
- Fixes Cocoapods deployment (#135)

## Version 2.0.4
- Upgrades PLCrashReporter (#122)
- Adds scoped attributes to PLCrashreport (#125)
- Adds extension to uploaded attachment (#126)
- Renames attributes and adds them as default (#127)
- Standardizes system attributes (#128)
- Updates FaultMessage Attribute to return Termination Signal name (#129)
- Upgrades COCOAPODS to ver 1.15.2 (#129)

## Version 2.0.3
- Added PrivacyInfo.xcprivacy

## Version 2.0.2
- Fixed infinity loop generated by the breadcrumb overflow
- Adjusted device.model attribute - now the attribute shows device model, rather than the model id

## Version 2.0.1
- Added application.session and application.version attribute as defaults - no matter if the metrics integration is enabled or not.
- Added application.build attribute that represents an app build version.
- Added backtrace.agent attribute that represents current agent name.

## Version 2.0.0
- Adds Swift Package Manager support
- Improves Breadcrumbs Swift implementation
- Remove static framework builds

## Version 1.7.5
- Fixed error.message values persists across multiple reports.
- Changed error emoji.

## Version 1.7.4
- No changes compared to 1.7.4-beta2

## Version 1.7.4-beta2
- Adds Call Observer breadcrumb in #97
- Prevents duplicate breadcrumbs in #92
- Improves OOM simulator and algorithm
- Improves build pipeline, automatic versioning and Xcode compatability in #96
- Fixes and prevents future usage the main thread for sync network calls

## Version 1.7.4-beta1
- Modifies the CI job to run tests daily on schedule in #81
- Skip file attachments that are larger than 10MB in #84
- Adds additional functionality for breadcrumbs in beta in #79
- Improves out of memory (OOM) reporting in #88 
- Updates README by @lysannep in #89

## Version 1.7.3
- Enables OOM reports for iOS version 15.3.1, and disables client side unwinding by default
- Added BETA Breadcrumbs implementation
- Updated BETA Crash Free metrics based on feedback from beta testing
- Updated build scripts

## Version 1.7.2
- Disable OOM reports for 15.3.1+ for backtrace-cocoa (so invalid OOM reports don't crash it)

## Version 1.7.1
- Make `hostname` attribute optional to prevent end-user from getting Local Network permissions pop-up

## Version 1.7.0
- Simplifies default file attachments API

## Version 1.6.1
- Allows default file attachments which will be sent for all live reports as well as crash reports
- This allows sending file attachments with crash reports

## Version 1.6.0
- Support for Out of memory detection - Backtrace-cocoa now allows to send information about low memory warnings that application received before application was killed by operating system.
- Backtrace-cocoa sets `error.type` attribute that our users can use to filter specific type of reports generated by libraries. List of possible error.types:
* reports generated in try/catch block will have error.type equal to `Exception`,
* crashes will have `error.type` attribute equal to `Crash`,
* out of memory exceptions will have `error.type` attribute equal to `Low memory`
- TravisCI improvements

## Version 1.5.6

- Allows injecting an instance of PLCrashReporter.
- Resolves the compilation issue on Xcode 10.

## Version 1.5.5
- Fix issue in Xcode 11 caused by URLSession response being captured before initialization.
- Fix dangling pointer - use withUnsafeMutableBytes in order to explicitly convert the argument to buffer pointer valid for a defined scope.
- Update dependencies, Fastfile and Travis CI configuration.
