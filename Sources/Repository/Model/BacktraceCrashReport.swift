
import Foundation

public struct BacktraceCrashReport {
    //swiftlint:disable legacy_hashing
    let hashValue: Int
    //swiftlint:enable legacy_hashing
    let reportData: Data

    init(report: Data, hashValue: Int? = nil) {
        self.reportData = report
        self.hashValue = hashValue ?? UUID().hashValue
    }
}

extension BacktraceCrashReport: Equatable {

}
