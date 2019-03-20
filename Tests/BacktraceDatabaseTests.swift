import Nimble
import Quick
@testable import Backtrace

final class BacktraceDatabaseTests: QuickSpec {
    
    override func spec() {
        describe("Crash reporter") {
            let crashReporter = CrashReporter()
            do {
                let repository = try PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())
                try repository.clear()
                for _ in 0...100 {
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try repository.save(report)
                }
                
                it("Last report", closure: {
                    do {
                        let report = try crashReporter.generateLiveReport(attributes: [:])
                        try repository.save(report)
                        if let fetchedReport = try repository.getLatest().first {
                            expect(fetchedReport.reportData).to(equal(report.reportData))
                        }
                    } catch {
                        fail(error.localizedDescription)
                    }
                })
                it("Last report", closure: {
                    do {
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
                    } catch {
                        fail(error.localizedDescription)
                    }
                })
                
            } catch {
                fail(error.localizedDescription)
            }
        }
    }
}
