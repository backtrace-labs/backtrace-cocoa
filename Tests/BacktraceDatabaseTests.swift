import Nimble
import Quick
import XCTest
@testable import Backtrace
#if SWIFT_PACKAGE
import Foundation
#endif

// Keep these repository scenarios in one spec so they share a serial on-disk lifecycle.
// swiftlint:disable:next type_body_length
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

                throwingIt("dead-letters payloads when optional sidecars are missing or unreadable") {
                    let payload = Data("dead-letter-sidecar-\(UUID().uuidString)".utf8)
                    let identifier = BacktraceReportIdentifier.pendingReportIdentifier(for: payload)
                    let unreadableSidecarUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-unreadable-sidecar-\(UUID().uuidString)",
                                              isDirectory: true)
                    let missingSidecarUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-missing-sidecar-\(UUID().uuidString).plist")
                    try FileManager.default.createDirectory(at: unreadableSidecarUrl,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: unreadableSidecarUrl) }

                    try repository.deadLetterPendingCrash(
                        data: payload,
                        rawSidecarPaths: [unreadableSidecarUrl.path, missingSidecarUrl.path],
                        diagnostics: ["original": "diagnostic"],
                        failure: FileError.invalidPropertyList
                    )

                    let reportDirectoryUrl = repository.metadataDirectoryUrl
                        .appendingPathComponent("DeadLetters", isDirectory: true)
                        .appendingPathComponent(identifier.uuidString, isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: reportDirectoryUrl) }
                    expect(try Data(contentsOf: reportDirectoryUrl
                        .appendingPathComponent("payload.plcrash", isDirectory: false)))
                        .to(equal(payload))
                    let stateData = try Data(contentsOf: reportDirectoryUrl
                        .appendingPathComponent("state.plist", isDirectory: false))
                    let state = try XCTUnwrap(PropertyListSerialization.propertyList(
                        from: stateData,
                        options: [],
                        format: nil
                    ) as? [String: Any])
                    let diagnostics = try XCTUnwrap(state["diagnostics"] as? [String: Any])
                    expect(diagnostics["original"] as? String).to(equal("diagnostic"))
                    expect(diagnostics[BacktracePendingCrashMetadata.deadLetterMissingSidecarsKey] as? Int)
                        .to(equal(1))
                    expect(diagnostics[BacktracePendingCrashMetadata.deadLetterSidecarCopyFailuresKey] as? Int)
                        .to(equal(1))
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

                throwingIt("skips and diagnoses a pending attachment that disappears after preflight") {
                    let sourceDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-attachment-toctou-\(UUID().uuidString)",
                                              isDirectory: true)
                    try FileManager.default.createDirectory(at: sourceDirectory,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: sourceDirectory) }
                    let sourceUrl = sourceDirectory.appendingPathComponent("pending.txt")
                    try Data("pending".utf8).write(to: sourceUrl)

                    var removedAfterPreflight = false
                    let toctouRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        attachmentResourceValues: { source in
                            if source.standardizedFileURL == sourceUrl.standardizedFileURL {
                                try FileManager.default.removeItem(at: source)
                                removedAfterPreflight = true
                            }
                            return try source.resourceValues(forKeys: [.isRegularFileKey])
                        }
                    )
                    try toctouRepository.clear()
                    defer { try? toctouRepository.clear() }
                    let pending = try BacktraceReport(
                        pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: [:],
                        attachmentPaths: [sourceUrl.path]
                    )

                    try toctouRepository.savePending(pending)

                    let stored = try XCTUnwrap(toctouRepository.getAll().first)
                    expect(removedAfterPreflight).to(beTrue())
                    expect(stored.attachmentPaths).to(beEmpty())
                    expect(stored.attributes[BacktracePendingCrashMetadata.missingAttachmentsKey] as? Int)
                        .to(equal(1))
                }

                throwingIt("keeps a pending crash source when destination attachment persistence fails") {
                    let sourceUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-attachment-destination-\(UUID().uuidString).txt")
                    try Data("pending".utf8).write(to: sourceUrl)
                    defer { try? FileManager.default.removeItem(at: sourceUrl) }
                    let failingRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        attachmentCopy: { _, _ in throw FileError.fileNotWritten }
                    )
                    try failingRepository.clear()
                    defer { try? failingRepository.clear() }
                    let pending = try BacktraceReport(
                        pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: [:],
                        attachmentPaths: [sourceUrl.path]
                    )

                    expect { try failingRepository.savePending(pending) }.to(throwError())

                    expect(FileManager.default.fileExists(atPath: sourceUrl.path)).to(beTrue())
                    expect(try failingRepository.countResources()).to(equal(0))
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
                    try repository.clear()
                    let liveReport = try crashReporter.generateLiveReport(attributes: [:])
                    for _ in 1...100 {
                        let group = DispatchGroup()
                        let report = try BacktraceReport(report: liveReport.reportData,
                                                         attributes: [:],
                                                         attachmentPaths: [])
                        DispatchQueue.global().async(group: group) {
                            do {
                                try repository.save(report)
                            } catch {
                                fail("Failed to save asynchronously: \(error)")
                            }
                        }
                        group.wait()
                    }
                    expect(try repository.countResources()).to(equal(100))
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

                throwingIt("serializes file and Core Data upserts for the same report identifier") {
                    try repository.clear()
                    let sourceDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-transaction-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: sourceDirectory,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: sourceDirectory) }

                    let liveReport = try crashReporter.generateLiveReport(attributes: [:])
                    let identifier = BacktraceReportIdentifier.pendingReportIdentifier(for: liveReport.reportData)
                    let group = DispatchGroup()
                    let errorLock = NSLock()
                    var errors = [Error]()

                    for generation in 0..<20 {
                        let source = sourceDirectory.appendingPathComponent("\(generation).txt")
                        try Data("\(generation)".utf8).write(to: source)
                        let report = try BacktraceReport(report: liveReport.reportData,
                                                         attributes: ["generation": generation],
                                                         attachmentPaths: [source.path],
                                                         identifier: identifier)
                        DispatchQueue.global().async(group: group) {
                            do {
                                try repository.save(report)
                            } catch {
                                errorLock.lock()
                                errors.append(error)
                                errorLock.unlock()
                            }
                        }
                    }
                    group.wait()

                    expect(errors).to(beEmpty())
                    expect(try repository.countResources()).to(equal(1))
                    let stored = try repository.getAll().first!
                    let storedGeneration = stored.attributes["generation"] as? Int
                    let attachmentPath = try XCTUnwrap(stored.attachmentPaths.first)
                    let attachmentGeneration = String(data: try Data(contentsOf: URL(fileURLWithPath: attachmentPath)),
                                                      encoding: .utf8)
                    expect(attachmentGeneration).to(equal(storedGeneration.map(String.init)))
                }

                throwingIt("rolls back Core Data mutations after a failed repository save") {
                    let failureLock = NSLock()
                    var shouldFailSave = true
                    let failingRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        contextSave: { context in
                            failureLock.lock()
                            defer { failureLock.unlock() }
                            if shouldFailSave {
                                shouldFailSave = false
                                throw FileError.fileNotWritten
                            }
                            try context.save()
                        }
                    )
                    let failedReport = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["transaction": "failed"],
                        attachmentPaths: []
                    )
                    let successfulReport = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["transaction": "successful"],
                        attachmentPaths: []
                    )

                    expect { try failingRepository.save(failedReport) }.to(throwError())
                    try failingRepository.save(successfulReport)

                    let identifiers = try failingRepository.getAll().map(\.identifier)
                    expect(identifiers).to(contain(successfulReport.identifier))
                    expect(identifiers).notTo(contain(failedReport.identifier))
                }

                throwingIt("rolls back capacity eviction when the final repository save fails") {
                    let settingsWithLimit = BacktraceDatabaseSettings()
                    settingsWithLimit.maxRecordCount = 1
                    let failureLock = NSLock()
                    var shouldFailSave = false
                    let limitedRepository = try PersistentRepository<BacktraceReport>(
                        settings: settingsWithLimit,
                        startupReconciliation: { _ in },
                        contextSave: { context in
                            failureLock.lock()
                            defer { failureLock.unlock() }
                            if shouldFailSave {
                                shouldFailSave = false
                                throw FileError.fileNotWritten
                            }
                            try context.save()
                        }
                    )
                    try limitedRepository.clear()
                    defer { try? limitedRepository.clear() }

                    let sourceDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-capacity-rollback-\(UUID().uuidString)",
                                              isDirectory: true)
                    try FileManager.default.createDirectory(at: sourceDirectory,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: sourceDirectory) }
                    let oldSource = sourceDirectory.appendingPathComponent("old.txt")
                    let failedSource = sourceDirectory.appendingPathComponent("failed.txt")
                    try Data("old".utf8).write(to: oldSource)
                    try Data("failed".utf8).write(to: failedSource)
                    let oldReport = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["transaction": "old"],
                        attachmentPaths: [oldSource.path]
                    )
                    let failedReport = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["transaction": "failed"],
                        attachmentPaths: [failedSource.path]
                    )
                    try limitedRepository.save(oldReport)
                    let oldOwnedPath = try XCTUnwrap(limitedRepository.getAll().first?.attachmentPaths.first)

                    failureLock.lock()
                    shouldFailSave = true
                    failureLock.unlock()
                    expect { try limitedRepository.save(failedReport) }.to(throwError())

                    let stored = try limitedRepository.getAll()
                    expect(stored.map(\.identifier)).to(equal([oldReport.identifier]))
                    expect(stored.first?.attributes["transaction"] as? String).to(equal("old"))
                    expect(FileManager.default.fileExists(atPath: oldOwnedPath)).to(beTrue())
                    expect(try Data(contentsOf: URL(fileURLWithPath: oldOwnedPath)))
                        .to(equal(Data("old".utf8)))
                    let failedAttachmentDirectory = limitedRepository.attachmentStore.rootUrl
                        .appendingPathComponent(failedReport.identifier.uuidString, isDirectory: true)
                    expect(FileManager.default.fileExists(atPath: failedAttachmentDirectory.path)).to(beFalse())
                }

                throwingIt("bounds physical database-size eviction to one committed victim per save") {
                    let settingsWithSizeLimit = BacktraceDatabaseSettings()
                    settingsWithSizeLimit.maxDatabaseSize = 1
                    let sizeLock = NSLock()
                    var exceedsLimit = false
                    let sizeLimitedRepository = try PersistentRepository<BacktraceReport>(
                        settings: settingsWithSizeLimit,
                        startupReconciliation: { _ in },
                        databaseSize: { _ in
                            sizeLock.lock()
                            defer { sizeLock.unlock() }
                            return exceedsLimit ? 2 * 1024 * 1024 : 0
                        }
                    )
                    try sizeLimitedRepository.clear()
                    defer { try? sizeLimitedRepository.clear() }

                    let reports = try (0..<4).map { index in
                        try BacktraceReport(
                            report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                            attributes: ["size-order": index],
                            attachmentPaths: []
                        )
                    }
                    for report in reports.prefix(3) {
                        try sizeLimitedRepository.save(report)
                    }

                    sizeLock.lock()
                    exceedsLimit = true
                    sizeLock.unlock()
                    try sizeLimitedRepository.save(reports[3])

                    let identifiers = Set(try sizeLimitedRepository.getAll().map(\.identifier))
                    expect(try sizeLimitedRepository.countResources()).to(equal(3))
                    expect(identifiers).notTo(contain(reports[0].identifier))
                    expect(identifiers).to(contain(reports[1].identifier,
                                                   reports[2].identifier,
                                                   reports[3].identifier))
                }

                throwingIt("keeps awaiting pending reports visible for inspection but out of replay fetches") {
                    try repository.clear()
                    let pending = try BacktraceReport(pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                                                      attributes: [:],
                                                      attachmentPaths: [])

                    try repository.savePending(pending)

                    expect(try repository.countResources()).to(equal(1))
                    expect(try repository.getAll().map(\.identifier)).to(contain(pending.identifier))
                    expect(try repository.getLatest()).to(beEmpty())
                    expect(try repository.getOldest()).to(beEmpty())

                    try repository.markReadyForSubmission(pending)
                    expect(try repository.getLatest().map(\.identifier)).to(equal([pending.identifier]))
                }

                throwingIt("keeps terminal rows out of replay until deferred cleanup succeeds") {
                    try repository.clear()
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try repository.save(report)

                    try repository.markTerminalForDeletion(report)

                    expect(try repository.countResources()).to(equal(1))
                    expect(try repository.getAll().map(\.identifier)).to(equal([report.identifier]))
                    expect(try repository.getLatest()).to(beEmpty())
                    expect(try repository.getOldest()).to(beEmpty())
                    expect(try repository.persistedState(for: report)).to(equal(.terminalAwaitingDeletion))

                    try repository.reconcileStorage()
                    expect(try repository.countResources()).to(equal(0))
                }

                throwingIt("recovers corrupt eligibility state using current source knowledge") {
                    try repository.clear()
                    let pending = try BacktraceReport(pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                                                      attributes: [:],
                                                      attachmentPaths: [])
                    try repository.savePending(pending)
                    let stateUrl = repository.metadataDirectoryUrl
                        .appendingPathComponent("report-states.plist", isDirectory: false)
                    try Data("corrupt eligibility state".utf8).write(to: stateUrl, options: .atomic)

                    try repository.markAwaitingReportsReady()

                    expect(try repository.getLatest().map(\.identifier)).to(equal([pending.identifier]))
                    expect(try repository.persistedState(for: pending)).to(equal(.readyForSubmission))
                }

                throwingIt("keeps the repository operational when startup orphan cleanup fails") {
                    let repositoryWithDeferredCleanup = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in throw FileError.fileNotWritten }
                    )
                    try repositoryWithDeferredCleanup.clear()
                    let report = try crashReporter.generateLiveReport(attributes: [:])

                    try repositoryWithDeferredCleanup.save(report)

                    expect(try repositoryWithDeferredCleanup.countResources()).to(equal(1))
                }

                throwingIt("cancels deferred repository maintenance after native shutdown") {
                    let deferredRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in throw FileError.fileNotWritten },
                        maintenanceRetryDelay: .milliseconds(250)
                    )
                    try deferredRepository.clear()
                    defer { try? deferredRepository.clear() }
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try deferredRepository.save(report)
                    try deferredRepository.markTerminalForDeletion(report)

                    deferredRepository.shutdownForNativeBridge()
                    try deferredRepository.reconcileStorage()
                    Thread.sleep(forTimeInterval: 0.35)

                    expect(deferredRepository.isShutdown).to(beTrue())
                    expect(try deferredRepository.countResources()).to(equal(1))
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
