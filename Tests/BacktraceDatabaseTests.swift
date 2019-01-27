import Nimble
import Quick
@testable import Backtrace

final class BacktraceDatabaseTests: QuickSpec {
    
    override func spec() {
        describe("Crash reporter") {
            let crashReporter = CrashReporter()
            do {
                let repository = try PersistentRepository<BacktraceCrashReport>(settings: BacktraceDatabaseSettings())
                try repository.clear()
                for _ in 0...100 {
                    let report = try crashReporter.generateLiveReport()
                    try repository.save(report)
                }
                
                it("Last report", closure: {
                    do {
                        let report = try crashReporter.generateLiveReport()
                        try repository.save(report)
                        if let fetchedReport = try repository.getLatest() {
                            expect(fetchedReport.reportData).to(equal(report.reportData))
                        }
                    } catch {
                        
                    }
                })
            } catch {
                fail(error.localizedDescription)
            }
        }
    }
}
