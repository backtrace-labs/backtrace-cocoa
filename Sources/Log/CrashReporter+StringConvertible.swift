import Foundation
import Backtrace_PLCrashReporter

protocol Composite {
    var children: [Composite] { get }
    var customDebugAttributes: [String: Any] { get }
    var customDebugName: String { get }
}

extension Composite {
    var children: [Composite] {
        return []
    }
}

extension PLCrashReport: Composite {
    var customDebugName: String {
        return "Report"
    }

    var children: [Composite] {
        return [self.systemInfo,
                self.machineInfo,
                self.applicationInfo,
                self.processInfo,
                self.signalInfo,
                self.machExceptionInfo,
                self.exceptionInfo
                ]
            .compactMap { $0 }
    }

    var customDebugAttributes: [String: Any] {
        return [
            "has machine info": hasMachineInfo,
            "has process info": hasProcessInfo,
            "has exception info": hasExceptionInfo,
            "uuid": uuidRef?.hashValue ?? -1
        ]
    }
}

extension Composite {
    fileprivate func format(indentionLevel: Int) -> String {
        let newline = "\n"
        let tab = "\t"
        let separator = ": "
        let indention: (Int) -> String = { String(repeating: tab, count: $0) }

        let name = indention(indentionLevel) + customDebugName + separator
        let attributes = customDebugAttributes
            .mapValues { "\($0)" }
            .map { indention(indentionLevel + 1) + $0.key + separator + $0.value }
        let children = self.children
            .map { $0.format(indentionLevel: indentionLevel + 1)}

        return [[name], attributes, children]
            .joined()
            .joined(separator: newline)
    }
}

extension PLCrashReport {
    var info: String {
        return format(indentionLevel: 0)
    }
}

extension PLCrashReportProcessInfo: Composite {
    var customDebugName: String {
        return "Process"
    }

    var customDebugAttributes: [String: Any] {
        return [
            "name": processName.orEmpty(),
            "id": processID,
            "path": processPath.orEmpty(),
            "parent name": parentProcessName.orEmpty(),
            "parent id": parentProcessID,
            "native": native,
            "start time": processStartTime?.timeIntervalSince1970 ?? 0
        ]
    }
}

extension PLCrashReportSignalInfo: Composite {

    var customDebugAttributes: [String: Any] {
        return [
            "name": name.orEmpty(),
            "code": code.orEmpty(),
            "address": address
        ]
    }

    var customDebugName: String {
        return "Signal"
    }
}

extension PLCrashReportApplicationInfo: Composite {
    var customDebugName: String {
        return "Application"
    }
    var customDebugAttributes: [String: Any] {
        return [
            "identifier": applicationIdentifier.orEmpty(),
            "version": applicationVersion.orEmpty()
        ]
    }
}

extension PLCrashReportSystemInfo: Composite {
    var customDebugName: String {
        return "System"
    }

    var customDebugAttributes: [String: Any] {

        return [
            "name": operatingSystem.rawValue,
            "version": operatingSystemVersion.orEmpty(),
            "build": operatingSystemBuild.orEmpty(),
            "timestamp": timestamp?.timeIntervalSince1970 ?? 0
        ]
    }
}

extension PLCrashReportMachineInfo: Composite {
    var customDebugName: String {
        return "Machine"
    }

    var customDebugAttributes: [String: Any] {

        return [
            "model name": modelName.orEmpty(),
            "processor count": processorCount,
            "logical processor count": logicalProcessorCount
        ]
    }
}

extension PLCrashReportProcessorInfo: Composite {
    var customDebugName: String {
        return "Processor"
    }

    var customDebugAttributes: [String: Any] {

        return [
            "type": type,
            "subtype": subtype,
            "encoding": typeEncoding.rawValue
        ]
    }
}

extension PLCrashReportMachExceptionInfo: Composite {
    var customDebugName: String {
        return "Mach exception"
    }

    var customDebugAttributes: [String: Any] {
        let codes = self.codes as? [UInt] ?? []
        return [
            "type": type,
            "codes": codes
        ]
    }
}

extension PLCrashReportExceptionInfo: Composite {
    var customDebugName: String {
        return "Exception info"
    }

    var children: [Composite] {
        return [self.stackFrames as? Composite]
            .compactMap { $0 }
    }

    var customDebugAttributes: [String: Any] {
        return [
            "name": exceptionName.orEmpty(),
            "reason": exceptionReason.orEmpty()
        ]
    }
}

extension PLCrashReportSymbolInfo: Composite {
    var customDebugName: String {
        return "Symbol"
    }

    var customDebugAttributes: [String: Any] {
        return [
            "symbol name": symbolName.orEmpty(),
            "start address": startAddress,
            "end address": endAddress
        ]
    }
}

extension PLCrashReportStackFrameInfo: Composite {
    var customDebugName: String {
        return "Stack frame"
    }

    var children: [Composite] {
        return [self.symbolInfo]
            .compactMap { $0 }
    }

    var customDebugAttributes: [String: Any] {
        return [
            "instruction pointer": instructionPointer
        ]
    }
}

private extension Optional where Wrapped == String {
    func orEmpty() -> String {
        switch self {
        case .some(let wrapped):
            return wrapped
        case .none:
            return "---"
        }
    }
}
