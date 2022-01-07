import Nimble
import Quick
@testable import Backtrace

final class BacktraceDatabaseTests: QuickSpec {

    override func spec() {
        describe("Crash reporter") {
            throwingContext("given all dependencies and empty database") {
                let crashReporter = BacktraceCrashReporter()
                let repository = try PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

                throwingIt("can clear database") {
                    try repository.clear()
                }

                throwingIt("can save reports which matches to the latest saved one") {
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try repository.save(report)
                    if let fetchedReport = try repository.getLatest().first {
                        expect(fetchedReport.reportData).to(equal(report.reportData))
                    }
                }

                throwingIt("can add new report and remove it") {
                    try repository.clear()
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try repository.save(report)
                    expect { try repository.countResources() }.to(equal(1))
                    if let fetchedReport = try repository.getLatest().first {
                        expect(fetchedReport.reportData).to(equal(report.reportData))
                        try repository.delete(fetchedReport)
                        expect { try repository.countResources() }.to(equal(0))
                    } else {
                        fail()
                    }
                }

                throwingIt("can add 100 new reports") {
                    for _ in 0...100 {
                        let report = try crashReporter.generateLiveReport(attributes: [:])
                        try repository.save(report)
                    }
                }
            }
        }
    }
}
