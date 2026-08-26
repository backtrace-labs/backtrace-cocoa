import Nimble
import Quick
@testable import Backtrace
#if SWIFT_PACKAGE
import Foundation
#endif

final class BacktraceDatabaseTests: QuickSpec {

    // swiftlint:disable:next function_body_length
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

                throwingIt("uses the embedded PLCrashReporter UUID for a pending payload") {
                    let liveReport = try crashReporter.generateLiveReport(attributes: [:])
                    let first = try BacktraceReport(pendingReport: liveReport.reportData,
                                                    attributes: [:],
                                                    attachmentPaths: [])
                    let second = try BacktraceReport(pendingReport: liveReport.reportData,
                                                     attributes: [:],
                                                     attachmentPaths: [])

                    expect(first.identifier).to(equal(second.identifier))
                    expect(first.identifier)
                        .to(equal(BacktraceReportIdentifier.embeddedIdentifier(for: liveReport.reportData)))
                }

                it("derives a deterministic digest identifier when a report has no embedded UUID") {
                    let payload = Data("legacy-plcrash-payload".utf8)
                    let first = BacktraceReportIdentifier.pendingReportIdentifier(
                        embeddedIdentifier: nil,
                        reportData: payload
                    )
                    let second = BacktraceReportIdentifier.pendingReportIdentifier(
                        embeddedIdentifier: nil,
                        reportData: payload
                    )

                    expect(first).to(equal(second))
                    expect(first).to(equal(BacktraceReportIdentifier.digestIdentifier(for: payload)))
                }

                throwingIt("upserts a report by identifier") {
                    try repository.clear()
                    let liveReport = try crashReporter.generateLiveReport(attributes: [:])
                    let identifier = BacktraceReportIdentifier.pendingReportIdentifier(for: liveReport.reportData)
                    let first = try BacktraceReport(report: liveReport.reportData,
                                                    attributes: ["generation": "first"],
                                                    attachmentPaths: [],
                                                    identifier: identifier)
                    let second = try BacktraceReport(report: liveReport.reportData,
                                                     attributes: ["generation": "second"],
                                                     attachmentPaths: [],
                                                     identifier: identifier)

                    try repository.save(first)
                    try repository.save(second)

                    expect(try repository.countResources()).to(equal(1))
                    expect(try repository.getLatest().first?.attributes["generation"] as? String)
                        .to(equal("second"))
                }

                throwingIt("copies attachments into immutable repository storage") {
                    try repository.clear()
                    let sourceDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-attachment-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: sourceDirectory,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: sourceDirectory) }

                    let firstSource = sourceDirectory.appendingPathComponent("first.txt")
                    let secondSource = sourceDirectory.appendingPathComponent("second.txt")
                    try Data("first".utf8).write(to: firstSource)
                    try Data("second".utf8).write(to: secondSource)

                    let liveReport = try crashReporter.generateLiveReport(attributes: [:])
                    let identifier = BacktraceReportIdentifier.pendingReportIdentifier(for: liveReport.reportData)
                    let first = try BacktraceReport(report: liveReport.reportData,
                                                    attributes: [:],
                                                    attachmentPaths: [firstSource.path],
                                                    identifier: identifier)
                    try repository.save(first)
                    let firstOwnedPath = try repository.getLatest().first!.attachmentPaths.first!

                    expect(repository.attachmentStore.contains(URL(fileURLWithPath: firstOwnedPath))).to(beTrue())
                    try FileManager.default.removeItem(at: firstSource)
                    expect(try Data(contentsOf: URL(fileURLWithPath: firstOwnedPath)))
                        .to(equal(Data("first".utf8)))

                    let second = try BacktraceReport(report: liveReport.reportData,
                                                     attributes: [:],
                                                     attachmentPaths: [secondSource.path],
                                                     identifier: identifier)
                    try repository.save(second)
                    let secondOwnedPath = try repository.getLatest().first!.attachmentPaths.first!
                    expect(secondOwnedPath).notTo(equal(firstOwnedPath))
                    expect(FileManager.default.fileExists(atPath: firstOwnedPath)).to(beTrue())

                    try repository.reconcileStorage()
                    expect(FileManager.default.fileExists(atPath: firstOwnedPath)).to(beFalse())
                    expect(FileManager.default.fileExists(atPath: secondOwnedPath)).to(beTrue())
                }

                throwingIt("preserves durable pending data when repeat sources disappear") {
                    try repository.clear()
                    let sourceDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-repeat-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: sourceDirectory,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: sourceDirectory) }

                    let source = sourceDirectory.appendingPathComponent("pending.txt")
                    try Data("pending".utf8).write(to: source)
                    let liveReport = try crashReporter.generateLiveReport(attributes: [:])
                    let identifier = BacktraceReportIdentifier.pendingReportIdentifier(for: liveReport.reportData)
                    let first = try BacktraceReport(report: liveReport.reportData,
                                                    attributes: ["durable": "value"],
                                                    attachmentPaths: [source.path],
                                                    identifier: identifier)
                    try repository.save(first)
                    let ownedPath = try repository.getLatest().first!.attachmentPaths.first!
                    try FileManager.default.removeItem(at: source)

                    let repeated = try BacktraceReport(report: liveReport.reportData,
                                                       attributes: [:],
                                                       attachmentPaths: [source.path],
                                                       identifier: identifier)
                    try repository.save(repeated)

                    let stored = try repository.getLatest().first!
                    expect(stored.attachmentPaths).to(equal([ownedPath]))
                    expect(FileManager.default.fileExists(atPath: ownedPath)).to(beTrue())
                    expect(stored.attributes["durable"] as? String).to(equal("value"))
                }

                throwingIt("removes repository symlinks without following them") {
                    let externalDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-external-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: externalDirectory,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: externalDirectory) }
                    let sentinel = externalDirectory.appendingPathComponent("sentinel.txt")
                    try Data("do-not-delete".utf8).write(to: sentinel)

                    let escapedDirectory = repository.attachmentStore.rootUrl
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createSymbolicLink(at: escapedDirectory,
                                                               withDestinationURL: externalDirectory)

                    try repository.reconcileStorage()

                    expect(FileManager.default.fileExists(atPath: escapedDirectory.path)).to(beFalse())
                    expect(FileManager.default.fileExists(atPath: sentinel.path)).to(beTrue())
                }

                throwingIt("resolves the packaged Core Data model") {
                    expect(PersistentRepository<BacktraceReport>.resolveModelUrl()).toNot(beNil())
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
