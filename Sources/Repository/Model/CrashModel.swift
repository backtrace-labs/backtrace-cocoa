//
//  CrashModel.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 22/12/2018.
//

import Foundation
import PLCrashReporter

public struct CrashModel {
    //swiftlint:disable legacy_hashing
    let hashValue: Int
    //swiftlint:enable legacy_hashing
    let reportData: Data

    init(report: Data, hashValue: Int? = nil) {
        self.reportData = report
        self.hashValue = hashValue ?? UUID().hashValue
    }
}

extension CrashModel: Equatable {

}

extension CrashModel: CustomStringConvertible {
    public var description: String {
        do {
            let report = try PLCrashReport(data: reportData)
            return report.info
        } catch {
            return "Crash report info unavailable"
        }
    }
}
