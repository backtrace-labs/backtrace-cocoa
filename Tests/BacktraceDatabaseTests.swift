import Nimble
import Quick
@testable import Backtrace
#if SWIFT_PACKAGE
import Foundation
#endif

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

                throwingIt("can add 100 new reports (async)") {
                    try? repository.clear()
                    for _ in 1...100 {
                        let group = DispatchGroup()
                        let report = try? crashReporter.generateLiveReport(attributes: [:])
                        DispatchQueue.global().async(group: group) {
                            try? repository.save(report!)
                        }
                        group.wait()
                    }
                    expect { try? repository.countResources() }.toEventually(equal(100))
                }
                
                throwingIt("supports concurrent read/write operations") {
                    try repository.clear()
                    
                    let writeGroup = DispatchGroup()
                    let readGroup = DispatchGroup()
                    
                    // concurrent writes
                    for _ in 1...5 {
                        writeGroup.enter()
                        DispatchQueue.global().async {
                            defer { writeGroup.leave() }
                            do {
                                let report = try crashReporter.generateLiveReport(attributes: [:])
                                try repository.save(report)
                            } catch {
                                fail("Failed to save concurrently: \(error)")
                            }
                        }
                    }
                    
                    // concurrent reads
                    for _ in 1...5 {
                        readGroup.enter()
                        DispatchQueue.global().async {
                            defer { readGroup.leave() }
                            do {
                                _ = try repository.getLatest()
                            } catch {
                                fail("Failed to fetch concurrently: \(error)")
                            }
                        }
                    }
                    
                    writeGroup.wait()
                    readGroup.wait()
                    expect(try? repository.countResources()).to(equal(5))
                }
                
                throwingIt("test with a custom maxRecordCount, removes oldest records when max record count is exceeded") {
                    let settingsWithLimit = BacktraceDatabaseSettings()
                    settingsWithLimit.maxRecordCount = 5
                    let limitedRepository = try PersistentRepository<BacktraceReport>(
                                            settings: settingsWithLimit)
                    try limitedRepository.clear()
                    // Insert 6 reports
                    let timeOrderedReports = try (1...6).map { _ -> BacktraceReport in
                        let report = try crashReporter.generateLiveReport(attributes: [:])
                        try limitedRepository.save(report)
                        return report
                    }
                    // Should remove oldest if limit is 5
                    let finalCount = try limitedRepository.countResources()
                    expect(finalCount).to(equal(5))

                    // check if the first inserted record is deleted
                    let firstInserted = timeOrderedReports.first!
                    let allResources = try limitedRepository.getAll()
                    expect(allResources).notTo(containElementSatisfying { $0.identifier == firstInserted.identifier })
                }
                
                throwingIt("increments retry count and removes resource when limit is exceeded") {
                    try repository.clear()
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try repository.save(report)
                    // First increment
                    try repository.incrementRetryCount(report, limit: 3)
                    // second increment
                    try repository.incrementRetryCount(report, limit: 3)
                    // getLatest should still return latest
                    let secondCheck = try repository.getLatest().first
                    expect(secondCheck).toNot(beNil())
                    // Exceed the limit
                    try repository.incrementRetryCount(report, limit: 2)
                    // Now it should be removed
                    expect { try repository.countResources() }.to(equal(0))
                }
            }
        }
    }
}
