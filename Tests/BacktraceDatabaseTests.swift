import Nimble
import Quick
import XCTest
import CoreData
@testable import Backtrace
#if SWIFT_PACKAGE
import Foundation
#endif

// Repository migration, file ownership, and cross-process cases share one serial on-disk spec.
// swiftlint:disable file_length

private enum RepositoryFileTestError: Error {
    case subprocessLeaseUnavailable
}

#if os(macOS)
/// Holds the same POSIX record lock used by the repository from a separate process.
private final class RepositoryFileLockProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()

    init(lockUrl: URL) {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            """
            import fcntl, os, sys
            descriptor = os.open(sys.argv[1], os.O_CREAT | os.O_RDWR, 0o600)
            fcntl.lockf(descriptor, fcntl.LOCK_EX)
            print("locked", flush=True)
            sys.stdin.readline()
            """,
            lockUrl.path
        ]
        process.standardInput = input
        process.standardOutput = output
    }

    var terminationStatus: Int32 {
        return process.terminationStatus
    }

    func start() throws {
        try process.run()
        let readyData = output.fileHandleForReading.readData(ofLength: 7)
        guard String(data: readyData, encoding: .utf8) == "locked\n" else {
            process.waitUntilExit()
            throw RepositoryFileTestError.subprocessLeaseUnavailable
        }
    }

    func stop() {
        guard process.isRunning else { return }
        try? input.fileHandleForWriting.write(contentsOf: Data("release\n".utf8))
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()
    }

    deinit {
        stop()
    }
}
#endif

// Keep these repository scenarios in one spec so they share a serial on-disk lifecycle.
// swiftlint:disable:next type_body_length
final class BacktraceDatabaseTests: QuickSpec {

    // swiftlint:disable:next function_body_length cyclomatic_complexity
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

                throwingIt("does not replace or revoke a retry claim during a duplicate upsert") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-retry-upsert-\(UUID().uuidString)", isDirectory: true)
                    let sourceDirectory = storeDirectory.appendingPathComponent("sources", isDirectory: true)
                    try FileManager.default.createDirectory(at: sourceDirectory,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectory) }
                    let originalSource = sourceDirectory.appendingPathComponent("original.txt")
                    let replacementSource = sourceDirectory.appendingPathComponent("replacement.txt")
                    try Data("original".utf8).write(to: originalSource)
                    try Data("replacement".utf8).write(to: replacementSource)
                    let owner = "retry-owner-\(UUID().uuidString)"
                    let firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory,
                        deliveryOwnerToken: owner,
                        deliveryOwnerIsAlive: { _ in true }
                    )
                    let secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        attachmentCopy: { _, _ in throw FileError.fileNotWritten },
                        storeDirectoryUrl: storeDirectory,
                        deliveryOwnerIsAlive: { _ in true }
                    )
                    let identifier = UUID()
                    let original = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["generation": "original"],
                        attachmentPaths: [originalSource.path],
                        identifier: identifier
                    )
                    let replacement = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["generation": "replacement"],
                        attachmentPaths: [replacementSource.path],
                        identifier: identifier
                    )
                    try firstRepository.save(original)
                    let originalPath = try XCTUnwrap(firstRepository.getAll().first?.attachmentPaths.first)
                    try firstRepository.claimRetrySubmission(original)

                    // The throwing copy closure proves the protected duplicate returns before file staging.
                    try secondRepository.save(replacement)

                    expect(try firstRepository.persistedState(for: original))
                        .to(equal(.retryInFlight))
                    expect(try firstRepository.persistedDeliveryOwner(for: original)).to(equal(owner))

                    let pendingOutcome = try secondRepository.savePending(replacement)
                    expect(pendingOutcome).to(equal(.alreadyOwned(.retryInFlight)))

                    let stored = try XCTUnwrap(firstRepository.getAll().first)
                    expect(try firstRepository.persistedState(for: stored)).to(equal(.retryInFlight))
                    expect(try firstRepository.persistedDeliveryOwner(for: stored)).to(equal(owner))
                    expect(stored.reportData).to(equal(original.reportData))
                    expect(stored.attributes["generation"] as? String).to(equal("original"))
                    expect(stored.attachmentPaths).to(equal([originalPath]))
                    expect(try Data(contentsOf: URL(fileURLWithPath: originalPath)))
                        .to(equal(Data("original".utf8)))

                    try firstRepository.markReadyForRetry(stored, incrementRetryCountWithLimit: 3)
                    expect(try firstRepository.persistedState(for: stored)).to(equal(.readyForRetry))
                    expect(try firstRepository.getLatest().map(\.identifier)).to(equal([identifier]))

                    // A later accepted or permanently rejected attempt uses the same terminal
                    // finalization path. A second duplicate still cannot interfere with it.
                    expect(try firstRepository.claimRetrySubmission(stored)).to(beTrue())
                    try secondRepository.save(replacement)
                    try firstRepository.markTerminalForDeletion(stored)
                    try firstRepository.delete(stored)
                    expect(try firstRepository.countResources()).to(equal(0))
                    expect(FileManager.default.fileExists(atPath: originalPath)).to(beFalse())
                }

                throwingIt("does not replace or revoke an initial claim during duplicate pending ingestion") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-initial-upsert-\(UUID().uuidString)", isDirectory: true)
                    let sourceDirectory = storeDirectory.appendingPathComponent("sources", isDirectory: true)
                    try FileManager.default.createDirectory(at: sourceDirectory,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectory) }
                    let originalSource = sourceDirectory.appendingPathComponent("original.txt")
                    let replacementSource = sourceDirectory.appendingPathComponent("replacement.txt")
                    try Data("original".utf8).write(to: originalSource)
                    try Data("replacement".utf8).write(to: replacementSource)
                    let owner = "initial-owner-\(UUID().uuidString)"
                    let firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory,
                        deliveryOwnerToken: owner,
                        deliveryOwnerIsAlive: { _ in true }
                    )
                    let secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        attachmentCopy: { _, _ in throw FileError.fileNotWritten },
                        storeDirectoryUrl: storeDirectory,
                        deliveryOwnerIsAlive: { _ in true }
                    )
                    let identifier = UUID()
                    let original = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["generation": "original"],
                        attachmentPaths: [originalSource.path],
                        identifier: identifier
                    )
                    let replacement = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["generation": "replacement"],
                        attachmentPaths: [replacementSource.path],
                        identifier: identifier
                    )
                    try firstRepository.savePending(original)
                    try firstRepository.promoteAfterSourcePurge(original)
                    let originalPath = try XCTUnwrap(firstRepository.getAll().first?.attachmentPaths.first)
                    try firstRepository.claimInitialSubmission(original)

                    try secondRepository.save(replacement)

                    expect(try firstRepository.persistedState(for: original))
                        .to(equal(.initialSubmissionInFlight))
                    expect(try firstRepository.persistedDeliveryOwner(for: original)).to(equal(owner))

                    let outcome = try secondRepository.savePending(replacement)

                    expect(outcome).to(equal(.alreadyOwned(.initialSubmissionInFlight)))
                    let stored = try XCTUnwrap(firstRepository.getAll().first)
                    expect(try firstRepository.persistedState(for: stored))
                        .to(equal(.initialSubmissionInFlight))
                    expect(try firstRepository.persistedDeliveryOwner(for: stored)).to(equal(owner))
                    expect(stored.reportData).to(equal(original.reportData))
                    expect(stored.attributes["generation"] as? String).to(equal("original"))
                    expect(stored.attachmentPaths).to(equal([originalPath]))
                    expect(try Data(contentsOf: URL(fileURLWithPath: originalPath)))
                        .to(equal(Data("original".utf8)))

                    try firstRepository.releaseInitialClaim(stored)
                    expect(try firstRepository.persistedState(for: stored))
                        .to(equal(.readyForInitialSubmission))
                }

                for statusCode in [200, 403, 503] {
                    throwingIt("preserves an initial claim during duplicate ingestion and finalizes HTTP \(statusCode)") {
                        let storeDirectory = FileManager.default.temporaryDirectory
                            .appendingPathComponent(
                                "backtrace-duplicate-finalization-\(UUID().uuidString)",
                                isDirectory: true
                            )
                        let sourceDirectory = storeDirectory.appendingPathComponent("sources", isDirectory: true)
                        try FileManager.default.createDirectory(at: sourceDirectory,
                                                                withIntermediateDirectories: true)
                        let owner = "submission-owner-\(UUID().uuidString)"
                        let firstRepository = try PersistentRepository<BacktraceReport>(
                            settings: BacktraceDatabaseSettings(),
                            startupReconciliation: { _ in },
                            storeDirectoryUrl: storeDirectory,
                            deliveryOwnerToken: owner,
                            deliveryOwnerIsAlive: { _ in true }
                        )
                        let secondRepository = try PersistentRepository<BacktraceReport>(
                            settings: BacktraceDatabaseSettings(),
                            startupReconciliation: { _ in },
                            attachmentCopy: { _, _ in throw FileError.fileNotWritten },
                            storeDirectoryUrl: storeDirectory,
                            deliveryOwnerIsAlive: { _ in true }
                        )
                        defer {
                            firstRepository.shutdownForNativeBridge()
                            secondRepository.shutdownForNativeBridge()
                            try? FileManager.default.removeItem(at: storeDirectory)
                        }

                        let originalSource = sourceDirectory.appendingPathComponent("original.txt")
                        let replacementSource = sourceDirectory.appendingPathComponent("replacement.txt")
                        try Data("original attachment".utf8).write(to: originalSource)
                        try Data("replacement attachment".utf8).write(to: replacementSource)
                        let payload = try crashReporter.generateLiveReport(attributes: [:]).reportData
                        let original = try BacktraceReport(
                            pendingReport: payload,
                            attributes: ["generation": "original"],
                            attachmentPaths: [originalSource.path]
                        )
                        let duplicate = try BacktraceReport(
                            pendingReport: payload,
                            attributes: ["generation": "duplicate"],
                            attachmentPaths: [replacementSource.path]
                        )
                        expect(duplicate.identifier).to(equal(original.identifier))
                        expect(try firstRepository.savePending(original)).to(equal(.awaitingSourcePurge))
                        try firstRepository.promoteAfterSourcePurge(original)
                        let originalAttachment = try XCTUnwrap(
                            firstRepository.getAll().first?.attachmentPaths.first
                        )

                        let session = URLSessionMock()
                        switch statusCode {
                        case 200:
                            session.response = MockOkResponse()
                        case 403:
                            session.response = Mock403Response()
                        default:
                            session.response = MockHttpResponse(statusCode: statusCode)
                        }
                        let api = BacktraceApi(
                            credentials: BacktraceCredentials(
                                submissionUrl: URL(string: "https://yourteam.backtrace.io")!
                            ),
                            session: session,
                            reportsPerMin: 30
                        )
                        let delegate = BacktraceClientDelegateMock()
                        var duplicateOutcome: PendingSaveOutcome?
                        var duplicateError: Error?
                        var stateDuringSubmission: PersistedReportState?
                        var ownerDuringSubmission: String?
                        var storedDuringSubmission: BacktraceReport?
                        delegate.willSendClosure = { report in
                            do {
                                duplicateOutcome = try secondRepository.savePending(duplicate)
                                guard let stored = try firstRepository.getAll().first else {
                                    throw RepositoryError.resourceNotFound
                                }
                                storedDuringSubmission = stored
                                stateDuringSubmission = try firstRepository.persistedState(for: stored)
                                ownerDuringSubmission = try firstRepository.persistedDeliveryOwner(for: stored)
                            } catch {
                                duplicateError = error
                            }
                            return report
                        }
                        api.delegate = delegate
                        let coordinator = BacktraceSubmissionCoordinator(
                            api: api,
                            repository: firstRepository,
                            retryLimit: 3
                        )

                        let receipt = coordinator.submit(original, origin: .pendingNativeCrash)

                        expect(receipt.pipelineEntered).to(beTrue())
                        expect(receipt.transportStarted).to(beTrue())
                        expect(session.requestCount).to(equal(1))
                        expect(duplicateError).to(beNil())
                        expect(duplicateOutcome).to(equal(.alreadyOwned(.initialSubmissionInFlight)))
                        expect(stateDuringSubmission).to(equal(.initialSubmissionInFlight))
                        expect(ownerDuringSubmission).to(equal(owner))
                        expect(storedDuringSubmission?.reportData).to(equal(original.reportData))
                        expect(storedDuringSubmission?.attributes["generation"] as? String)
                            .to(equal("original"))
                        expect(storedDuringSubmission?.attachmentPaths).to(equal([originalAttachment]))
                        expect(duplicate.attachmentPaths).to(equal([originalAttachment]))

                        if statusCode == 503 {
                            expect(receipt.result.submissionDisposition).to(equal(.retryable))
                            expect(try firstRepository.countResources()).to(equal(1))
                            expect(try firstRepository.persistedState(for: original)).to(equal(.readyForRetry))
                            expect(try firstRepository.persistedDeliveryOwner(for: original)).to(beNil())
                            expect(try firstRepository.getLatest().map(\.identifier))
                                .to(equal([original.identifier]))
                            expect(FileManager.default.fileExists(atPath: originalAttachment)).to(beTrue())
                        } else {
                            let expectedDisposition: BacktraceSubmissionDisposition =
                                statusCode == 200 ? .accepted : .permanentFailure
                            expect(receipt.result.submissionDisposition).to(equal(expectedDisposition))
                            expect(try firstRepository.countResources()).to(equal(0))
                            expect(FileManager.default.fileExists(atPath: originalAttachment)).to(beFalse())
                        }
                    }
                }

                throwingIt("keeps a terminal row immutable during a duplicate save") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-terminal-upsert-\(UUID().uuidString)", isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectory) }
                    let firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory
                    )
                    let secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory
                    )
                    let identifier = UUID()
                    let original = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["generation": "original"],
                        attachmentPaths: [],
                        identifier: identifier
                    )
                    let replacement = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["generation": "replacement"],
                        attachmentPaths: [],
                        identifier: identifier
                    )
                    try firstRepository.save(original)
                    try firstRepository.markTerminalForDeletion(original)

                    try secondRepository.save(replacement)

                    let stored = try XCTUnwrap(firstRepository.getAll().first)
                    expect(try firstRepository.persistedState(for: stored))
                        .to(equal(.terminalAwaitingDeletion))
                    expect(stored.reportData).to(equal(original.reportData))
                    expect(stored.attributes["generation"] as? String).to(equal("original"))
                    expect(try firstRepository.getLatest()).to(beEmpty())
                    expect(try firstRepository.getInitialSubmission(count: 1)).to(beEmpty())

                    try firstRepository.delete(stored)
                    expect(try firstRepository.countResources()).to(equal(0))
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
                    let modelUrl = try XCTUnwrap(
                        PersistentRepository<BacktraceReport>.resolveModelUrl()
                    )
                    let modelV2Url = modelUrl.appendingPathComponent("ModelV2.mom")
                    let modelV2 = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelV2Url))
                    let crashEntity = try XCTUnwrap(modelV2.entitiesByName["Crash"])

                    expect(Set(crashEntity.attributesByName.keys)).to(equal(Set([
                        "attachmentPaths",
                        "dateAdded",
                        "deliveryOwner",
                        "deliveryStateRaw",
                        "hashProperty",
                        "reportData",
                        "retryCount"
                    ])))
                }

                throwingIt("skips an unrelated generic model without the V2 schema") {
                    let candidateRoot = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-model-candidates-\(UUID().uuidString)",
                                              isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: candidateRoot) }
                    let unrelatedUrl = candidateRoot.appendingPathComponent("Unrelated.momd",
                                                                            isDirectory: true)
                    let compatibleUrl = candidateRoot.appendingPathComponent("Backtrace.momd",
                                                                             isDirectory: true)
                    try FileManager.default.createDirectory(at: unrelatedUrl,
                                                            withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: compatibleUrl,
                                                            withIntermediateDirectories: true)
                    try Data().write(to: compatibleUrl.appendingPathComponent("ModelV2.mom"))

                    let resolved = PersistentRepository<BacktraceReport>.selectCompatibleModelUrl(
                        [unrelatedUrl, compatibleUrl]
                    )

                    expect(resolved).to(equal(compatibleUrl))
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
                    try repository.clear()
                    let liveReport = try crashReporter.generateLiveReport(attributes: [:])
                    for _ in 1...100 {
                        let report = try BacktraceReport(report: liveReport.reportData,
                                                         attributes: [:],
                                                         attachmentPaths: [])
                        try repository.save(report)
                    }
                    expect(try repository.countResources()).to(equal(100))
                }

                throwingIt("supports concurrent read/write operations") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-concurrent-repository-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    try FileManager.default.createDirectory(
                        at: storeDirectory,
                        withIntermediateDirectories: true
                    )

                    let concurrentRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory
                    )

                    // PLCrashReporter live-report generation owns process-global files. Generate
                    // once on this thread so this test isolates repository concurrency only.
                    let payload = try crashReporter.generateLiveReport(attributes: [:]).reportData
                    let reports = try (0..<5).map { index in
                        try BacktraceReport(
                            report: payload,
                            attributes: ["index": index],
                            attachmentPaths: [],
                            identifier: UUID()
                        )
                    }
                    let group = DispatchGroup()
                    let errorLock = NSLock()
                    var errors = [Error]()
                    var workersCompleted = false

                    defer {
                        if workersCompleted {
                            concurrentRepository.shutdownForNativeBridge()
                            try? FileManager.default.removeItem(at: storeDirectory)
                        } else {
                            // A timeout must fail promptly without tearing the store down under a
                            // worker. Let the workers retain the repository and clean up when done.
                            group.notify(queue: .global()) {
                                concurrentRepository.shutdownForNativeBridge()
                                try? FileManager.default.removeItem(at: storeDirectory)
                            }
                        }
                    }

                    func record(_ error: Error) {
                        errorLock.lock()
                        errors.append(error)
                        errorLock.unlock()
                    }

                    for report in reports {
                        group.enter()
                        DispatchQueue.global().async {
                            defer { group.leave() }
                            do {
                                try concurrentRepository.save(report)
                            } catch {
                                record(error)
                            }
                        }
                    }

                    for _ in 0..<5 {
                        group.enter()
                        DispatchQueue.global().async {
                            defer { group.leave() }
                            do {
                                _ = try concurrentRepository.getLatest()
                            } catch {
                                record(error)
                            }
                        }
                    }

                    let waitResult = group.wait(timeout: .now() + 10)
                    expect(waitResult).to(equal(.success))
                    guard waitResult == .success else { return }
                    workersCompleted = true

                    errorLock.lock()
                    let capturedErrors = errors
                    errorLock.unlock()

                    expect(capturedErrors).to(beEmpty())
                    expect(try concurrentRepository.countResources()).to(equal(5))
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

                for capacityMode in ["record count", "database size"] {
                    for originName in ["retry", "initial"] {
                        for statusCode in [200, 503] {
                            throwingIt("protects a \(originName) claim from \(capacityMode) eviction through HTTP \(statusCode)") {
                                let storeDirectory = FileManager.default.temporaryDirectory
                                    .appendingPathComponent(
                                        "backtrace-capacity-matrix-\(UUID().uuidString)",
                                        isDirectory: true
                                    )
                                let sourceDirectory = storeDirectory.appendingPathComponent(
                                    "sources",
                                    isDirectory: true
                                )
                                try FileManager.default.createDirectory(
                                    at: sourceDirectory,
                                    withIntermediateDirectories: true
                                )
                                let settings = BacktraceDatabaseSettings()
                                if capacityMode == "record count" {
                                    settings.maxRecordCount = 1
                                } else {
                                    settings.maxDatabaseSize = 1
                                }
                                let sizeLock = NSLock()
                                var exceedsDatabaseLimit = false
                                let owner = "capacity-owner-\(UUID().uuidString)"
                                let limitedRepository = try PersistentRepository<BacktraceReport>(
                                    settings: settings,
                                    startupReconciliation: { _ in },
                                    databaseSize: { _ in
                                        sizeLock.lock()
                                        defer { sizeLock.unlock() }
                                        return exceedsDatabaseLimit ? 2 * 1024 * 1024 : 0
                                    },
                                    maintenanceRetryDelay: .seconds(60),
                                    storeDirectoryUrl: storeDirectory,
                                    deliveryOwnerToken: owner,
                                    deliveryOwnerIsAlive: { _ in true }
                                )
                                defer {
                                    limitedRepository.shutdownForNativeBridge()
                                    try? FileManager.default.removeItem(at: storeDirectory)
                                }

                                let source = sourceDirectory.appendingPathComponent("active.txt")
                                try Data("active attachment".utf8).write(to: source)
                                let activePayload = try crashReporter
                                    .generateLiveReport(attributes: [:]).reportData
                                let active: BacktraceReport
                                let origin: BacktraceSubmissionOrigin
                                let expectedInFlightState: PersistedReportState
                                if originName == "initial" {
                                    active = try BacktraceReport(
                                        pendingReport: activePayload,
                                        attributes: ["capacity": "active-initial"],
                                        attachmentPaths: [source.path]
                                    )
                                    expect(try limitedRepository.savePending(active))
                                        .to(equal(.awaitingSourcePurge))
                                    try limitedRepository.promoteAfterSourcePurge(active)
                                    origin = .pendingNativeCrash
                                    expectedInFlightState = .initialSubmissionInFlight
                                } else {
                                    active = try BacktraceReport(
                                        report: activePayload,
                                        attributes: ["capacity": "active-retry"],
                                        attachmentPaths: [source.path]
                                    )
                                    try limitedRepository.save(active)
                                    origin = .repositoryRetry
                                    expectedInFlightState = .retryInFlight
                                }
                                let activeAttachment = try XCTUnwrap(
                                    limitedRepository.getAll().first?.attachmentPaths.first
                                )
                                let overflow = try BacktraceReport(
                                    report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                                    attributes: ["capacity": "overflow"],
                                    attachmentPaths: []
                                )
                                sizeLock.lock()
                                exceedsDatabaseLimit = true
                                sizeLock.unlock()

                                let session = URLSessionMock()
                                session.response = statusCode == 200
                                    ? MockOkResponse()
                                    : MockHttpResponse(statusCode: statusCode)
                                let api = BacktraceApi(
                                    credentials: BacktraceCredentials(
                                        submissionUrl: URL(string: "https://yourteam.backtrace.io")!
                                    ),
                                    session: session,
                                    reportsPerMin: 30
                                )
                                let delegate = BacktraceClientDelegateMock()
                                var callbackError: Error?
                                var activeStateDuringSubmission: PersistedReportState?
                                var activeOwnerDuringSubmission: String?
                                var overflowStateDuringSubmission: PersistedReportState?
                                var countDuringSubmission: Int?
                                var attachmentDataDuringSubmission: Data?
                                delegate.willSendClosure = { report in
                                    do {
                                        try limitedRepository.save(overflow)
                                        guard try limitedRepository.claimRetrySubmission(overflow) else {
                                            throw RepositoryError.resourceNotFound
                                        }
                                        try limitedRepository.reconcileStorage()
                                        activeStateDuringSubmission = try limitedRepository
                                            .persistedState(for: active)
                                        activeOwnerDuringSubmission = try limitedRepository
                                            .persistedDeliveryOwner(for: active)
                                        overflowStateDuringSubmission = try limitedRepository
                                            .persistedState(for: overflow)
                                        countDuringSubmission = try limitedRepository.countResources()
                                        attachmentDataDuringSubmission = try Data(
                                            contentsOf: URL(fileURLWithPath: activeAttachment)
                                        )
                                    } catch {
                                        callbackError = error
                                    }
                                    return report
                                }
                                api.delegate = delegate
                                let coordinator = BacktraceSubmissionCoordinator(
                                    api: api,
                                    repository: limitedRepository,
                                    retryLimit: 3
                                )

                                let receipt = coordinator.submit(active, origin: origin)

                                expect(callbackError).to(beNil())
                                expect(receipt.pipelineEntered).to(beTrue())
                                expect(receipt.transportStarted).to(beTrue())
                                expect(activeStateDuringSubmission).to(equal(expectedInFlightState))
                                expect(activeOwnerDuringSubmission).to(equal(owner))
                                expect(overflowStateDuringSubmission).to(equal(.retryInFlight))
                                expect(countDuringSubmission).to(equal(2))
                                expect(attachmentDataDuringSubmission)
                                    .to(equal(Data("active attachment".utf8)))

                                if statusCode == 503 {
                                    expect(receipt.result.submissionDisposition).to(equal(.retryable))
                                    expect(try limitedRepository.persistedState(for: active))
                                        .to(equal(.readyForRetry))
                                    expect(try limitedRepository.persistedDeliveryOwner(for: active)).to(beNil())
                                    expect(try limitedRepository.getLatest().map(\.identifier))
                                        .to(equal([active.identifier]))
                                    expect(FileManager.default.fileExists(atPath: activeAttachment)).to(beTrue())

                                    // A is now safely evictable; B remains protected by its claim.
                                    try limitedRepository.reconcileStorage()
                                    expect(try limitedRepository.getAll().map(\.identifier))
                                        .to(equal([overflow.identifier]))
                                    expect(FileManager.default.fileExists(atPath: activeAttachment)).to(beFalse())
                                } else {
                                    expect(receipt.result.submissionDisposition).to(equal(.accepted))
                                    expect(try limitedRepository.getAll().map(\.identifier))
                                        .to(equal([overflow.identifier]))
                                    expect(FileManager.default.fileExists(atPath: activeAttachment)).to(beFalse())
                                }

                                try limitedRepository.markReadyForRetry(
                                    overflow,
                                    incrementRetryCountWithLimit: 3
                                )
                                try limitedRepository.reconcileStorage()
                                let expectedFinalCount = capacityMode == "record count" ? 1 : 0
                                expect(try limitedRepository.countResources())
                                    .to(equal(expectedFinalCount))
                            }
                        }
                    }
                }

                throwingIt("reconciles deferred capacity after recovering an abandoned claim") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-recovered-capacity-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settings = BacktraceDatabaseSettings()
                    settings.maxRecordCount = 1
                    let livenessLock = NSLock()
                    var ownerIsAlive = true
                    let recoveringRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        maintenanceRetryDelay: .milliseconds(10),
                        storeDirectoryUrl: storeDirectory,
                        deliveryOwnerToken: "abandoned-capacity-owner",
                        deliveryOwnerIsAlive: { _ in
                            livenessLock.lock()
                            defer { livenessLock.unlock() }
                            return ownerIsAlive
                        }
                    )
                    defer {
                        recoveringRepository.shutdownForNativeBridge()
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let abandoned = try crashReporter.generateLiveReport(attributes: ["capacity": "abandoned"])
                    let survivor = try crashReporter.generateLiveReport(attributes: ["capacity": "survivor"])
                    try recoveringRepository.save(abandoned)
                    expect(try recoveringRepository.claimRetrySubmission(abandoned)).to(beTrue())
                    try recoveringRepository.save(survivor)
                    expect(try recoveringRepository.countResources()).to(equal(2))

                    livenessLock.lock()
                    ownerIsAlive = false
                    livenessLock.unlock()
                    _ = try recoveringRepository.getLatest()

                    expect { try recoveringRepository.countResources() }.toEventually(
                        equal(1),
                        timeout: .seconds(2)
                    )
                    expect(try recoveringRepository.getAll().map(\.identifier))
                        .to(equal([survivor.identifier]))
                }

                throwingIt("reconciles an insertion that overflowed behind a protected row") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-insert-overflow-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settings = BacktraceDatabaseSettings()
                    settings.maxRecordCount = 1
                    let overflowRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        maintenanceRetryDelay: .milliseconds(50),
                        storeDirectoryUrl: storeDirectory,
                        deliveryOwnerToken: "insert-overflow-owner",
                        deliveryOwnerIsAlive: { _ in true }
                    )
                    defer {
                        overflowRepository.shutdownForNativeBridge()
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let protected = try crashReporter.generateLiveReport(attributes: ["capacity": "protected"])
                    let overflow = try crashReporter.generateLiveReport(attributes: ["capacity": "overflow"])
                    try overflowRepository.save(protected)
                    expect(try overflowRepository.claimRetrySubmission(protected)).to(beTrue())
                    try overflowRepository.save(overflow)
                    expect(try overflowRepository.countResources()).to(equal(2))

                    expect { try overflowRepository.countResources() }.toEventually(
                        equal(1),
                        timeout: .seconds(2)
                    )
                    expect(try overflowRepository.getAll().map(\.identifier))
                        .to(equal([protected.identifier]))
                    expect(try overflowRepository.persistedState(for: protected))
                        .to(equal(.retryInFlight))
                }

                throwingIt("reconciles capacity after bulk source-handoff promotion") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-bulk-promotion-capacity-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settings = BacktraceDatabaseSettings()
                    settings.maxRecordCount = 1
                    let promotionRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        maintenanceRetryDelay: .milliseconds(10),
                        storeDirectoryUrl: storeDirectory
                    )
                    defer {
                        promotionRepository.shutdownForNativeBridge()
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let first = try BacktraceReport(
                        pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["capacity": "first"],
                        attachmentPaths: []
                    )
                    let second = try BacktraceReport(
                        pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["capacity": "second"],
                        attachmentPaths: []
                    )
                    try promotionRepository.savePending(first)
                    try promotionRepository.savePending(second)
                    expect(try promotionRepository.countResources()).to(equal(2))

                    try promotionRepository.markAwaitingReportsReady()

                    expect { try promotionRepository.countResources() }.toEventually(
                        equal(1),
                        timeout: .seconds(2)
                    )
                    expect(try promotionRepository.getAll().map(\.identifier))
                        .to(equal([second.identifier]))
                    expect(try promotionRepository.persistedState(for: second))
                        .to(equal(.readyForInitialSubmission))
                }

                throwingIt("coalesces a transition burst into one database-size maintenance victim") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-coalesced-capacity-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settings = BacktraceDatabaseSettings()
                    let sizeLock = NSLock()
                    var exceedsLimit = false
                    var enforcementChecks = 0
                    let coalescingRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        databaseSize: { _ in
                            sizeLock.lock()
                            defer { sizeLock.unlock() }
                            if exceedsLimit {
                                enforcementChecks += 1
                                return 2 * 1024 * 1024
                            }
                            return 0
                        },
                        maintenanceRetryDelay: .milliseconds(50),
                        storeDirectoryUrl: storeDirectory
                    )
                    defer {
                        coalescingRepository.shutdownForNativeBridge()
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let reports = try (0..<3).map { index in
                        try crashReporter.generateLiveReport(attributes: ["capacity": index])
                    }
                    for report in reports {
                        try coalescingRepository.save(report)
                        expect(try coalescingRepository.claimRetrySubmission(report)).to(beTrue())
                    }
                    settings.maxDatabaseSize = 1
                    sizeLock.lock()
                    exceedsLimit = true
                    sizeLock.unlock()

                    for report in reports {
                        try coalescingRepository.markReadyForRetry(report)
                    }

                    expect { try coalescingRepository.countResources() }.toEventually(
                        equal(2),
                        timeout: .seconds(2)
                    )
                    sizeLock.lock()
                    let capturedEnforcementChecks = enforcementChecks
                    sizeLock.unlock()
                    expect(capturedEnforcementChecks).to(equal(1))
                }

                throwingIt("reruns capacity maintenance when a new request arrives during a pass") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-overlapping-capacity-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settings = BacktraceDatabaseSettings()
                    let stateLock = NSLock()
                    var exceedsLimit = false
                    var releaseSecondReport = false
                    var overlapError: Error?
                    var overlappingRepository: PersistentRepository<BacktraceReport>!
                    var secondReport: BacktraceReport!
                    overlappingRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        databaseSize: { _ in
                            stateLock.lock()
                            let currentExceedsLimit = exceedsLimit
                            stateLock.unlock()
                            return currentExceedsLimit ? 2 * 1024 * 1024 : 0
                        },
                        maintenanceRetryDelay: .milliseconds(10),
                        capacityReconciliationDidRun: { repository in
                            stateLock.lock()
                            let shouldReleaseSecondReport = releaseSecondReport
                            releaseSecondReport = false
                            stateLock.unlock()
                            guard shouldReleaseSecondReport else { return }
                            do {
                                try repository.markReadyForRetry(secondReport)
                            } catch {
                                stateLock.lock()
                                overlapError = error
                                stateLock.unlock()
                            }
                        },
                        storeDirectoryUrl: storeDirectory
                    )
                    defer {
                        overlappingRepository.shutdownForNativeBridge()
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let firstReport = try crashReporter.generateLiveReport(attributes: ["capacity": "first"])
                    secondReport = try crashReporter.generateLiveReport(attributes: ["capacity": "second"])
                    try overlappingRepository.save(firstReport)
                    try overlappingRepository.save(secondReport)
                    expect(try overlappingRepository.claimRetrySubmission(firstReport)).to(beTrue())
                    expect(try overlappingRepository.claimRetrySubmission(secondReport)).to(beTrue())

                    settings.maxDatabaseSize = 1
                    stateLock.lock()
                    exceedsLimit = true
                    releaseSecondReport = true
                    stateLock.unlock()
                    try overlappingRepository.markReadyForRetry(firstReport)

                    expect { try overlappingRepository.countResources() }.toEventually(
                        equal(0),
                        timeout: .seconds(2)
                    )
                    stateLock.lock()
                    let capturedOverlapError = overlapError
                    stateLock.unlock()
                    expect(capturedOverlapError).to(beNil())
                }

                throwingIt("evicts safe rows by delivery priority and protects source handoffs") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-capacity-rank-\(UUID().uuidString)", isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectory) }
                    let settings = BacktraceDatabaseSettings()
                    settings.maxRecordCount = 3
                    let rankedRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory
                    )
                    func report(_ label: String) throws -> BacktraceReport {
                        try BacktraceReport(
                            report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                            attributes: ["rank": label],
                            attachmentPaths: []
                        )
                    }
                    let sourceHandoff = try report("source-handoff")
                    let initial = try report("initial")
                    let terminal = try report("terminal")
                    let retry = try report("retry")
                    let newest = try report("newest")
                    try rankedRepository.savePending(sourceHandoff)
                    try rankedRepository.savePending(initial)
                    try rankedRepository.promoteAfterSourcePurge(initial)
                    try rankedRepository.save(terminal)
                    try rankedRepository.markTerminalForDeletion(terminal)

                    try rankedRepository.save(retry)

                    var identifiers = Set(try rankedRepository.getAll().map(\.identifier))
                    expect(identifiers).notTo(contain(terminal.identifier))
                    expect(identifiers).to(contain(sourceHandoff.identifier,
                                                  initial.identifier,
                                                  retry.identifier))

                    try rankedRepository.save(newest)

                    identifiers = Set(try rankedRepository.getAll().map(\.identifier))
                    expect(identifiers).notTo(contain(retry.identifier))
                    expect(identifiers).to(contain(sourceHandoff.identifier,
                                                  initial.identifier,
                                                  newest.identifier))
                    expect(try rankedRepository.persistedState(for: sourceHandoff))
                        .to(equal(.awaitingSourcePurge))
                }

                throwingIt("fails closed for an unknown non-null persisted delivery state") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-unknown-delivery-state-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settings = BacktraceDatabaseSettings()
                    settings.maxRecordCount = 1
                    let isolatedRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory
                    )
                    defer {
                        isolatedRepository.shutdownForNativeBridge()
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let quarantined = try BacktraceReport(
                        report: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["state": "unknown"],
                        attachmentPaths: []
                    )
                    try isolatedRepository.save(quarantined)
                    try isolatedRepository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(entityName: BacktraceReport.entityName)
                        guard let object = try isolatedRepository.backgroundContext.fetch(request).first else {
                            throw RepositoryError.resourceNotFound
                        }
                        object.setValue(NSNumber(value: Int16.max), forKey: "deliveryStateRaw")
                        try isolatedRepository.backgroundContext.save()
                    }

                    expect(try isolatedRepository.persistedState(for: quarantined))
                        .to(equal(.invalidPersistedState))
                    expect(try isolatedRepository.getLatest()).to(beEmpty())
                    expect(try isolatedRepository.getInitialSubmission(count: 1)).to(beEmpty())

                    let eligible = try crashReporter.generateLiveReport(attributes: [:])
                    try isolatedRepository.save(eligible)
                    expect(try isolatedRepository.countResources()).to(equal(2))
                    try isolatedRepository.reconcileStorage()

                    expect(try isolatedRepository.getAll().map(\.identifier))
                        .to(equal([quarantined.identifier]))
                    expect(try isolatedRepository.persistedState(for: quarantined))
                        .to(equal(.invalidPersistedState))
                }

                throwingIt("separates a pending report's initial attempt from ordinary retry") {
                    try repository.clear()
                    let pending = try BacktraceReport(pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                                                      attributes: [:],
                                                      attachmentPaths: [])

                    try repository.savePending(pending)

                    expect(try repository.countResources()).to(equal(1))
                    expect(try repository.getAll().map(\.identifier)).to(contain(pending.identifier))
                    expect(try repository.getLatest()).to(beEmpty())
                    expect(try repository.getOldest()).to(beEmpty())
                    expect(try repository.getInitialSubmission(count: 1)).to(beEmpty())

                    try repository.promoteAfterSourcePurge(pending)
                    expect(try repository.getLatest()).to(beEmpty())
                    expect(try repository.getInitialSubmission(count: 1).map(\.identifier))
                        .to(equal([pending.identifier]))
                    expect(try repository.claimInitialSubmission(pending)).to(beTrue())
                    expect(try repository.claimInitialSubmission(pending)).to(beFalse())
                    expect(try repository.persistedState(for: pending)).to(equal(.initialSubmissionInFlight))

                    try repository.markReadyForRetry(pending)
                    expect(try repository.getInitialSubmission(count: 1)).to(beEmpty())
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

                throwingIt("migrates a real v1 store without losing retry rows or attachments") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-model-migration-\(UUID().uuidString)",
                                              isDirectory: true)
                    try FileManager.default.createDirectory(at: storeDirectoryUrl,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectoryUrl) }

                    let attachmentUrl = storeDirectoryUrl.appendingPathComponent("legacy-attachment.txt")
                    try Data("legacy attachment".utf8).write(to: attachmentUrl)
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    let storeUrl = storeDirectoryUrl.appendingPathComponent("Model.sqlite")
                    let modelDirectoryUrl = try XCTUnwrap(
                        PersistentRepository<BacktraceReport>.resolveModelUrl()
                    )
                    let legacyModelUrl = modelDirectoryUrl.appendingPathComponent("Model.mom")
                    let legacyModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: legacyModelUrl))

                    do {
                        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: legacyModel)
                        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                        context.persistentStoreCoordinator = coordinator
                        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType,
                                                                        configurationName: nil,
                                                                        at: storeUrl,
                                                                        options: nil)
                        try context.performAndWaitThrowing {
                            let entity = try XCTUnwrap(NSEntityDescription.entity(forEntityName: "Crash",
                                                                                  in: context))
                            let legacyRow = NSManagedObject(entity: entity, insertInto: context)
                            legacyRow.setValue(report.identifier.uuidString, forKey: "hashProperty")
                            legacyRow.setValue(report.reportData, forKey: "reportData")
                            legacyRow.setValue([attachmentUrl.path], forKey: "attachmentPaths")
                            legacyRow.setValue(Date(), forKey: "dateAdded")
                            legacyRow.setValue(2, forKey: "retryCount")

                            try context.save()
                        }
                        try coordinator.remove(store)
                    }

                    let migratedRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let migrated = try XCTUnwrap(migratedRepository.getLatest().first)

                    expect(migrated.identifier).to(equal(report.identifier))
                    expect(migrated.attachmentPaths).to(equal([attachmentUrl.path]))
                    expect(FileManager.default.fileExists(atPath: attachmentUrl.path)).to(beTrue())
                    expect(try migratedRepository.persistedState(for: migrated)).to(equal(.readyForRetry))
                    expect(try migratedRepository.countResources()).to(equal(1))
                }

                throwingIt("serializes claims made by two repository instances") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-shared-repository-\(UUID().uuidString)",
                                              isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectoryUrl) }
                    let firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try firstRepository.save(report)

                    let claims = try [firstRepository, secondRepository].map {
                        try $0.claimRetrySubmission(report)
                    }

                    expect(claims.filter { $0 }).to(haveCount(1))
                    expect(try secondRepository.persistedState(for: report)).to(equal(.retryInFlight))
                    try secondRepository.resetInFlightReports()
                    expect(try firstRepository.persistedState(for: report)).to(equal(.readyForRetry))
                }

                throwingIt("does not rewind a live claim when a second repository performs startup recovery") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-once-per-process-recovery-\(UUID().uuidString)",
                                              isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectoryUrl) }
                    let firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    try firstRepository.recoverStaleInFlightReportsOncePerProcess()
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try firstRepository.save(report)
                    expect(try firstRepository.claimRetrySubmission(report)).to(beTrue())

                    let secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    try secondRepository.recoverStaleInFlightReportsOncePerProcess()

                    expect(try secondRepository.persistedState(for: report)).to(equal(.retryInFlight))
                    expect(try secondRepository.claimRetrySubmission(report)).to(beFalse())
                }

                throwingIt("does not recover an in-flight row owned by a live foreign process") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-live-foreign-owner-\(UUID().uuidString)",
                                              isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectoryUrl) }
                    let foreignOwner = UUID().uuidString
                    let foreignRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: foreignOwner
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try foreignRepository.save(report)
                    expect(try foreignRepository.claimRetrySubmission(report)).to(beTrue())

                    let recoveringRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: UUID().uuidString,
                        deliveryOwnerIsAlive: { $0 == foreignOwner }
                    )
                    try recoveringRepository.recoverStaleInFlightReportsOncePerProcess()

                    expect(try recoveringRepository.persistedState(for: report)).to(equal(.retryInFlight))
                    expect(try recoveringRepository.persistedDeliveryOwner(for: report)).to(equal(foreignOwner))
                }

                throwingIt("recovers a foreign claim when its lease expires after startup") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-expired-owner-after-startup-\(UUID().uuidString)",
                                              isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectoryUrl) }
                    let foreignOwner = UUID().uuidString
                    let foreignRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: foreignOwner
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try foreignRepository.save(report)
                    expect(try foreignRepository.claimRetrySubmission(report)).to(beTrue())

                    var foreignOwnerIsAlive = true
                    let recoveringRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: UUID().uuidString,
                        deliveryOwnerIsAlive: { owner in
                            owner == foreignOwner && foreignOwnerIsAlive
                        }
                    )
                    try recoveringRepository.recoverStaleInFlightReportsOncePerProcess()
                    expect(try recoveringRepository.getOldest(count: 1)).to(beEmpty())
                    expect(try recoveringRepository.persistedState(for: report)).to(equal(.retryInFlight))

                    foreignOwnerIsAlive = false
                    expect(try recoveringRepository.getOldest(count: 1).map(\.identifier))
                        .to(equal([report.identifier]))
                    expect(try recoveringRepository.persistedState(for: report)).to(equal(.readyForRetry))
                    expect(try recoveringRepository.persistedDeliveryOwner(for: report)).to(beNil())
                }

#if os(macOS)
                throwingIt("uses a cross-process lease to protect and later recover an active claim") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-subprocess-owner-\(UUID().uuidString)",
                                              isDirectory: true)
                    let foreignOwner = UUID().uuidString
                    let leaseDirectoryUrl = storeDirectoryUrl
                        .appendingPathComponent("BacktraceReportLocks", isDirectory: true)
                        .appendingPathComponent("Leases", isDirectory: true)
                    let leaseUrl = leaseDirectoryUrl
                        .appendingPathComponent("\(foreignOwner).lock", isDirectory: false)
                    let leaseProcess = RepositoryFileLockProcess(lockUrl: leaseUrl)
                    var sourceRepository: PersistentRepository<BacktraceReport>?
                    var recoveringRepository: PersistentRepository<BacktraceReport>?
                    defer {
                        leaseProcess.stop()
                        recoveringRepository = nil
                        sourceRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }

                    sourceRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: foreignOwner
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try sourceRepository?.save(report)
                    expect(try sourceRepository?.claimRetrySubmission(report)).to(beTrue())

                    try FileManager.default.createDirectory(at: leaseDirectoryUrl,
                                                            withIntermediateDirectories: true)
                    try leaseProcess.start()

                    recoveringRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    try recoveringRepository?.recoverStaleInFlightReportsOncePerProcess()
                    expect(try recoveringRepository?.getOldest(count: 1)).to(beEmpty())
                    expect(try recoveringRepository?.persistedState(for: report)).to(equal(.retryInFlight))

                    leaseProcess.stop()
                    expect(leaseProcess.terminationStatus).to(equal(0))

                    expect(try recoveringRepository?.getOldest(count: 1).map(\.identifier))
                        .to(equal([report.identifier]))
                    expect(try recoveringRepository?.persistedState(for: report)).to(equal(.readyForRetry))
                    expect(try recoveringRepository?.persistedDeliveryOwner(for: report)).to(beNil())
                }

                throwingIt("serializes process lease creation with the database lock") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-serialized-lease-\(UUID().uuidString)",
                                              isDirectory: true)
                    try FileManager.default.createDirectory(at: storeDirectoryUrl,
                                                            withIntermediateDirectories: true)
                    let databaseUrl = storeDirectoryUrl.appendingPathComponent("Model.sqlite")
                    let databaseLockUrl = databaseUrl.appendingPathExtension("backtrace.lock")
                    let leaseDirectoryUrl = storeDirectoryUrl
                        .appendingPathComponent("BacktraceReportLocks", isDirectory: true)
                        .appendingPathComponent("Leases", isDirectory: true)
                    let databaseLockProcess = RepositoryFileLockProcess(lockUrl: databaseLockUrl)
                    let initializationFinished = DispatchSemaphore(value: 0)
                    let resultLock = NSLock()
                    var initializedRepository: PersistentRepository<BacktraceReport>?
                    var initializationError: Error?
                    var initializationWasJoined = false
                    defer {
                        databaseLockProcess.stop()
                        if !initializationWasJoined {
                            _ = initializationFinished.wait(timeout: .now() + 5)
                        }
                        initializedRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }

                    try databaseLockProcess.start()
                    DispatchQueue.global().async {
                        do {
                            let repository = try PersistentRepository<BacktraceReport>(
                                settings: BacktraceDatabaseSettings(),
                                startupReconciliation: { _ in },
                                storeDirectoryUrl: storeDirectoryUrl
                            )
                            resultLock.lock()
                            initializedRepository = repository
                            resultLock.unlock()
                        } catch {
                            resultLock.lock()
                            initializationError = error
                            resultLock.unlock()
                        }
                        initializationFinished.signal()
                    }

                    expect(initializationFinished.wait(timeout: .now() + .milliseconds(250)))
                        .to(equal(.timedOut))
                    expect(FileManager.default.fileExists(atPath: leaseDirectoryUrl.path)).to(beFalse())

                    databaseLockProcess.stop()
                    let initializationResult = initializationFinished.wait(timeout: .now() + 5)
                    expect(initializationResult).to(equal(.success))
                    initializationWasJoined = initializationResult == .success
                    resultLock.lock()
                    let repositoryWasInitialized = initializedRepository != nil
                    let capturedError = initializationError
                    resultLock.unlock()
                    expect(repositoryWasInitialized).to(beTrue())
                    expect(capturedError).to(beNil())
                    let leaseFiles = try FileManager.default.contentsOfDirectory(at: leaseDirectoryUrl,
                                                                                 includingPropertiesForKeys: nil)
                    expect(leaseFiles.filter { $0.pathExtension == "lock" }).to(haveCount(1))
                }

                throwingIt("fails closed when a foreign owner lease cannot be opened") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-owner-open-failure-\(UUID().uuidString)",
                                              isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectoryUrl) }
                    let foreignOwner = UUID().uuidString
                    let sourceRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: foreignOwner
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try sourceRepository.save(report)
                    expect(try sourceRepository.claimRetrySubmission(report)).to(beTrue())

                    let ownerLeaseUrl = storeDirectoryUrl
                        .appendingPathComponent("BacktraceReportLocks", isDirectory: true)
                        .appendingPathComponent("Leases", isDirectory: true)
                        .appendingPathComponent("\(foreignOwner).lock", isDirectory: true)
                    try FileManager.default.createDirectory(at: ownerLeaseUrl,
                                                            withIntermediateDirectories: true)
                    let recoveringRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    try recoveringRepository.recoverStaleInFlightReportsOncePerProcess()

                    expect(try recoveringRepository.persistedState(for: report)).to(equal(.retryInFlight))
                    expect(try recoveringRepository.persistedDeliveryOwner(for: report)).to(equal(foreignOwner))
                }
#endif

                throwingIt("recovers an in-flight row after its foreign process lease expires") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-dead-foreign-owner-\(UUID().uuidString)",
                                              isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectoryUrl) }
                    let foreignRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: UUID().uuidString
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try foreignRepository.save(report)
                    expect(try foreignRepository.claimRetrySubmission(report)).to(beTrue())

                    let recoveringRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: UUID().uuidString,
                        deliveryOwnerIsAlive: { _ in false }
                    )
                    try recoveringRepository.recoverStaleInFlightReportsOncePerProcess()

                    expect(try recoveringRepository.persistedState(for: report)).to(equal(.readyForRetry))
                    expect(try recoveringRepository.persistedDeliveryOwner(for: report)).to(beNil())
                }

                throwingIt("retries once-per-process recovery after its transaction fails") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-failed-stale-recovery-\(UUID().uuidString)",
                                              isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectoryUrl) }
                    let sourceRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try sourceRepository.save(report)
                    expect(try sourceRepository.claimRetrySubmission(report)).to(beTrue())

                    let failingRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        contextSave: { _ in throw FileError.fileNotWritten },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerIsAlive: { _ in false }
                    )
                    expect {
                        try failingRepository.recoverStaleInFlightReportsOncePerProcess()
                    }.to(throwError())
                    expect(try sourceRepository.persistedState(for: report)).to(equal(.retryInFlight))

                    let recoveringRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerIsAlive: { _ in false }
                    )
                    try recoveringRepository.recoverStaleInFlightReportsOncePerProcess()
                    expect(try recoveringRepository.persistedState(for: report)).to(equal(.readyForRetry))
                }

                throwingIt("accounts retry completion before another repository can claim the row") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-atomic-retry-\(UUID().uuidString)",
                                              isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectoryUrl) }
                    let firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try firstRepository.save(report)
                    expect(try firstRepository.claimRetrySubmission(report)).to(beTrue())

                    try firstRepository.markReadyForRetry(report, incrementRetryCountWithLimit: 3)

                    expect(try secondRepository.claimRetrySubmission(report)).to(beTrue())
                    try secondRepository.markReadyForRetry(report, incrementRetryCountWithLimit: 0)
                    expect(try firstRepository.countResources()).to(equal(0))
                    expect(try firstRepository.claimRetrySubmission(report)).to(beFalse())
                }

                throwingIt("does not reactivate an in-flight row when terminal marking and deletion both fail") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-terminal-failure-\(UUID().uuidString)",
                                              isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: storeDirectoryUrl) }
                    let saveLock = NSLock()
                    var shouldFail = false
                    let failingRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        contextSave: { context in
                            saveLock.lock()
                            defer { saveLock.unlock() }
                            if shouldFail {
                                throw FileError.fileNotWritten
                            }
                            try context.save()
                        },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try failingRepository.save(report)
                    expect(try failingRepository.claimRetrySubmission(report)).to(beTrue())

                    saveLock.lock()
                    shouldFail = true
                    saveLock.unlock()
                    expect { try failingRepository.markTerminalForDeletion(report) }.to(throwError())
                    expect { try failingRepository.delete(report) }.to(throwError())

                    expect(try failingRepository.persistedState(for: report)).to(equal(.retryInFlight))
                    expect(try failingRepository.getLatest()).to(beEmpty())
                    expect(try failingRepository.getInitialSubmission(count: 1)).to(beEmpty())
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
