#if BACKTRACE_UNITY_PREFIXED_PLCRASHREPORTER
import BTUnityCrashReporter

/// The private Unity artifact builds PLCrashReporter with `PLCRASHREPORTER_PREFIX=BTUnity`.
/// Keep the rest of the Cocoa SDK source independent of that private namespace.
public typealias PLCrashReporter = BTUnityPLCrashReporter
public typealias PLCrashReporterConfig = BTUnityPLCrashReporterConfig
public typealias PLCrashReport = BTUnityPLCrashReport
public typealias PLCrashReportTextFormatter = BTUnityPLCrashReportTextFormatter
#endif
