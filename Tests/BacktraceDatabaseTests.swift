import Nimble
import Quick
import XCTest
import CoreData
@testable import Backtrace
#if canImport(Darwin)
import Darwin
#endif
#if SWIFT_PACKAGE
import Foundation
#endif

// Repository migration, file ownership, and cross-process cases share one serial on-disk spec.
// swiftlint:disable file_length

private enum RepositoryFileTestError: Error {
    case subprocessLeaseUnavailable
}

#if canImport(Darwin)
private func openDarwinFileDescriptorCount() -> Int {
    return (0..<Darwin.getdtablesize()).reduce(into: 0) { count, descriptor in
        if Darwin.fcntl(descriptor, F_GETFD) != -1 {
            count += 1
        }
    }
}
#endif

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
                let repositoryStoreDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "backtrace-database-spec-\(UUID().uuidString)",
                        isDirectory: true
                    )
                var repository: PersistentRepository<BacktraceReport>! = try PersistentRepository<BacktraceReport>(
                    settings: BacktraceDatabaseSettings(),
                    startupReconciliation: { _ in },
                    storeDirectoryUrl: repositoryStoreDirectory
                )
                throwingAfterSuite {
                    repository.shutdownForNativeBridge()
                    repository = nil
                    try? FileManager.default.removeItem(at: repositoryStoreDirectory)
                }

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
                    var firstRepository: PersistentRepository<BacktraceReport>!
                    var secondRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        firstRepository?.shutdownForNativeBridge()
                        secondRepository?.shutdownForNativeBridge()
                        firstRepository = nil
                        secondRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let originalSource = sourceDirectory.appendingPathComponent("original.txt")
                    let replacementSource = sourceDirectory.appendingPathComponent("replacement.txt")
                    try Data("original".utf8).write(to: originalSource)
                    try Data("replacement".utf8).write(to: replacementSource)
                    let owner = "retry-owner-\(UUID().uuidString)"
                    firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory,
                        deliveryOwnerToken: owner,
                        deliveryOwnerIsAlive: { _ in true }
                    )
                    secondRepository = try PersistentRepository<BacktraceReport>(
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
                    _ = try firstRepository.claimRetrySubmission(original)

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
                    expect(try firstRepository.claimRetrySubmission(stored)).toNot(beNil())
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
                    var firstRepository: PersistentRepository<BacktraceReport>!
                    var secondRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        firstRepository?.shutdownForNativeBridge()
                        secondRepository?.shutdownForNativeBridge()
                        firstRepository = nil
                        secondRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let originalSource = sourceDirectory.appendingPathComponent("original.txt")
                    let replacementSource = sourceDirectory.appendingPathComponent("replacement.txt")
                    try Data("original".utf8).write(to: originalSource)
                    try Data("replacement".utf8).write(to: replacementSource)
                    let owner = "initial-owner-\(UUID().uuidString)"
                    firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory,
                        deliveryOwnerToken: owner,
                        deliveryOwnerIsAlive: { _ in true }
                    )
                    secondRepository = try PersistentRepository<BacktraceReport>(
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
                    _ = try firstRepository.claimInitialSubmission(original)

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

                let atomicClaimScenarios: [(name: String, origin: BacktraceSubmissionOrigin)] = [
                    ("initial", .pendingNativeCrash),
                    ("retry", .repositoryRetry)
                ]

                for scenario in atomicClaimScenarios {
                    throwingIt(
                        "submits the current durable \(scenario.name) snapshot when content changes before claim"
                    ) {
                        let storeDirectory = FileManager.default.temporaryDirectory
                            .appendingPathComponent(
                                "backtrace-atomic-claim-\(UUID().uuidString)",
                                isDirectory: true
                            )
                        let sourceDirectory = storeDirectory
                            .appendingPathComponent("sources", isDirectory: true)
                        try FileManager.default.createDirectory(
                            at: sourceDirectory,
                            withIntermediateDirectories: true
                        )

                        var firstRepository: PersistentRepository<BacktraceReport>!
                        var secondRepository: PersistentRepository<BacktraceReport>!
                        defer {
                            firstRepository?.shutdownForNativeBridge()
                            secondRepository?.shutdownForNativeBridge()
                            firstRepository = nil
                            secondRepository = nil
                            try? FileManager.default.removeItem(at: storeDirectory)
                        }
                        firstRepository = try PersistentRepository<BacktraceReport>(
                            settings: BacktraceDatabaseSettings(),
                            startupReconciliation: { _ in },
                            storeDirectoryUrl: storeDirectory
                        )
                        secondRepository = try PersistentRepository<BacktraceReport>(
                            settings: BacktraceDatabaseSettings(),
                            startupReconciliation: { _ in },
                            storeDirectoryUrl: storeDirectory
                        )

                        let originalSource = sourceDirectory.appendingPathComponent("original.txt")
                        let replacementSource = sourceDirectory.appendingPathComponent("replacement.txt")
                        try Data("original".utf8).write(to: originalSource)
                        try Data("replacement".utf8).write(to: replacementSource)

                        let payload = try crashReporter.generateLiveReport(attributes: [:]).reportData
                        let identifier = UUID()
                        let original = try BacktraceReport(
                            report: payload,
                            attributes: ["snapshot": "original"],
                            attachmentPaths: [originalSource.path],
                            identifier: identifier
                        )
                        let replacement = try BacktraceReport(
                            report: payload,
                            attributes: ["snapshot": "replacement"],
                            attachmentPaths: [replacementSource.path],
                            identifier: identifier
                        )

                        let stale: BacktraceReport

                        switch scenario.origin {
                        case .pendingNativeCrash:
                            expect(try firstRepository.savePending(original))
                                .to(equal(.awaitingSourcePurge))
                            try firstRepository.promoteAfterSourcePurge(original)
                            stale = try XCTUnwrap(
                                firstRepository.getInitialSubmission(count: 1).first
                            )
                            expect(try secondRepository.savePending(replacement))
                                .to(equal(.alreadyOwned(.readyForInitialSubmission)))
                        case .repositoryRetry:
                            try firstRepository.save(original)
                            stale = try XCTUnwrap(firstRepository.getLatest().first)
                            try secondRepository.save(replacement)
                        case .live, .outOfMemory:
                            fail("Unexpected atomic-claim test origin")
                            return
                        }

                        let staleAttachment = try XCTUnwrap(stale.attachmentPaths.first)
                        let current = try XCTUnwrap(firstRepository.getAll().first)
                        let currentAttachment = try XCTUnwrap(current.attachmentPaths.first)

                        expect(stale.attributes["snapshot"] as? String).to(equal("original"))
                        expect(current.attributes["snapshot"] as? String).to(equal("replacement"))
                        expect(currentAttachment).notTo(equal(staleAttachment))

                        try secondRepository.reconcileStorage()

                        expect(FileManager.default.fileExists(atPath: staleAttachment)).to(beFalse())
                        expect(FileManager.default.fileExists(atPath: currentAttachment)).to(beTrue())

                        let session = URLSessionMock()
                        session.response = MockOkResponse()
                        let api = BacktraceApi(
                            credentials: BacktraceCredentials(
                                submissionUrl: URL(string: "https://yourteam.backtrace.io")!
                            ),
                            session: session,
                            reportsPerMin: 30
                        )

                        var submittedSnapshot: String?
                        var submittedAttachmentPath: String?
                        var submittedAttachmentData: Data?
                        var stateDuringSubmission: PersistedReportState?
                        let delegate = BacktraceClientDelegateMock()
                        delegate.willSendClosure = { report in
                            submittedSnapshot = report.attributes["snapshot"] as? String
                            submittedAttachmentPath = report.attachmentPaths.first
                            stateDuringSubmission = try? firstRepository.persistedState(for: report)
                            if let path = submittedAttachmentPath {
                                submittedAttachmentData = try? Data(
                                    contentsOf: URL(fileURLWithPath: path)
                                )
                            }
                            return report
                        }
                        api.delegate = delegate

                        var coordinator: BacktraceSubmissionCoordinator<
                            PersistentRepository<BacktraceReport>
                        >? = BacktraceSubmissionCoordinator(
                            api: api,
                            repository: firstRepository,
                            retryLimit: 3
                        )
                        let receipt = coordinator!.submit(stale, origin: scenario.origin)
                        coordinator = nil

                        expect(receipt.pipelineEntered).to(beTrue())
                        expect(receipt.transportStarted).to(beTrue())
                        expect(receipt.result.submissionDisposition).to(equal(.accepted))
                        expect(session.requestCount).to(equal(1))
                        expect(submittedSnapshot).to(equal("replacement"))
                        expect(submittedAttachmentPath).to(equal(currentAttachment))
                        expect(submittedAttachmentData).to(equal(Data("replacement".utf8)))
                        let expectedState: PersistedReportState = scenario.origin == .pendingNativeCrash
                            ? .initialSubmissionInFlight
                            : .retryInFlight
                        expect(stateDuringSubmission).to(equal(expectedState))
                        expect(receipt.result.report?.attributes["snapshot"] as? String)
                            .to(equal("replacement"))
                        expect(try firstRepository.countResources()).to(equal(0))
                        expect(FileManager.default.fileExists(atPath: currentAttachment)).to(beFalse())
                    }
                }

                throwingIt("keeps the claimed retry snapshot after retryable finalization") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-atomic-retry-snapshot-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    var firstRepository: PersistentRepository<BacktraceReport>!
                    var secondRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        firstRepository?.shutdownForNativeBridge()
                        secondRepository?.shutdownForNativeBridge()
                        firstRepository = nil
                        secondRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory
                    )
                    secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory
                    )

                    let identifier = UUID()
                    let originalPayload = try crashReporter.generateLiveReport(
                        attributes: ["payload": "original"]
                    ).reportData
                    let replacementPayload = try crashReporter.generateLiveReport(
                        attributes: ["payload": "replacement"]
                    ).reportData
                    let original = try BacktraceReport(
                        report: originalPayload,
                        attributes: ["snapshot": "original"],
                        attachmentPaths: [],
                        identifier: identifier
                    )
                    let replacement = try BacktraceReport(
                        report: replacementPayload,
                        attributes: ["snapshot": "replacement"],
                        attachmentPaths: [],
                        identifier: identifier
                    )

                    try firstRepository.save(original)
                    let stale = try XCTUnwrap(firstRepository.getLatest().first)
                    try secondRepository.save(replacement)

                    expect(stale.reportData).to(equal(originalPayload))
                    expect(replacementPayload).notTo(equal(originalPayload))

                    let session = URLSessionMock()
                    session.response = MockHttpResponse(statusCode: 503)
                    let api = BacktraceApi(
                        credentials: BacktraceCredentials(
                            submissionUrl: URL(string: "https://yourteam.backtrace.io")!
                        ),
                        session: session,
                        reportsPerMin: 30
                    )
                    var submittedPayload: Data?
                    let delegate = BacktraceClientDelegateMock()
                    delegate.willSendClosure = { report in
                        submittedPayload = report.reportData
                        return report
                    }
                    api.delegate = delegate

                    var coordinator: BacktraceSubmissionCoordinator<
                        PersistentRepository<BacktraceReport>
                    >? = BacktraceSubmissionCoordinator(
                        api: api,
                        repository: firstRepository,
                        retryLimit: 3
                    )
                    let receipt = coordinator!.submit(stale, origin: .repositoryRetry)
                    coordinator = nil

                    expect(receipt.pipelineEntered).to(beTrue())
                    expect(receipt.transportStarted).to(beTrue())
                    expect(receipt.result.submissionDisposition).to(equal(.retryable))
                    expect(submittedPayload).to(equal(replacementPayload))

                    let stored = try XCTUnwrap(firstRepository.getLatest().first)
                    expect(stored.reportData).to(equal(replacementPayload))
                    expect(stored.attributes["snapshot"] as? String).to(equal("replacement"))
                    expect(try firstRepository.persistedState(for: stored)).to(equal(.readyForRetry))
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
                        var firstRepository: PersistentRepository<BacktraceReport>!
                        var secondRepository: PersistentRepository<BacktraceReport>!
                        defer {
                            firstRepository?.shutdownForNativeBridge()
                            secondRepository?.shutdownForNativeBridge()
                            firstRepository = nil
                            secondRepository = nil
                            try? FileManager.default.removeItem(at: storeDirectory)
                        }
                        firstRepository = try PersistentRepository<BacktraceReport>(
                            settings: BacktraceDatabaseSettings(),
                            startupReconciliation: { _ in },
                            storeDirectoryUrl: storeDirectory,
                            deliveryOwnerToken: owner,
                            deliveryOwnerIsAlive: { _ in true }
                        )
                        secondRepository = try PersistentRepository<BacktraceReport>(
                            settings: BacktraceDatabaseSettings(),
                            startupReconciliation: { _ in },
                            attachmentCopy: { _, _ in throw FileError.fileNotWritten },
                            storeDirectoryUrl: storeDirectory,
                            deliveryOwnerIsAlive: { _ in true }
                        )

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
                        var coordinator: BacktraceSubmissionCoordinator<
                            PersistentRepository<BacktraceReport>
                        >? = BacktraceSubmissionCoordinator(
                            api: api,
                            repository: firstRepository,
                            retryLimit: 3
                        )

                        let receipt = coordinator!.submit(original, origin: .pendingNativeCrash)
                        coordinator = nil

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
                    var firstRepository: PersistentRepository<BacktraceReport>!
                    var secondRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        firstRepository?.shutdownForNativeBridge()
                        secondRepository?.shutdownForNativeBridge()
                        firstRepository = nil
                        secondRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory
                    )
                    secondRepository = try PersistentRepository<BacktraceReport>(
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

                throwingIt("copies attachments and removes superseded immutable generations") {
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
                    expect(FileManager.default.fileExists(atPath: firstOwnedPath)).to(beFalse())

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

                    var concurrentRepository: PersistentRepository<BacktraceReport>!
                    let group = DispatchGroup()
                    let errorLock = NSLock()
                    var errors = [Error]()
                    var workersCompleted = false

                    defer {
                        if workersCompleted {
                            concurrentRepository?.shutdownForNativeBridge()
                            concurrentRepository = nil
                            try? FileManager.default.removeItem(at: storeDirectory)
                        } else {
                            // A timeout must fail promptly without tearing the store down under a
                            // worker. Let the workers retain the repository and clean up when done.
                            group.notify(queue: .global()) {
                                concurrentRepository?.shutdownForNativeBridge()
                                concurrentRepository = nil
                                try? FileManager.default.removeItem(at: storeDirectory)
                            }
                        }
                    }
                    concurrentRepository = try PersistentRepository<BacktraceReport>(
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
                    let reportAttachmentDirectory = repository.attachmentStore.rootUrl
                        .appendingPathComponent(identifier.uuidString, isDirectory: true)
                    let persistedGenerations = try FileManager.default.contentsOfDirectory(
                        at: reportAttachmentDirectory,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )
                    expect(persistedGenerations.count).to(equal(1))
                    expect(persistedGenerations.first?.standardizedFileURL.path)
                        .to(equal(URL(fileURLWithPath: attachmentPath)
                            .deletingLastPathComponent().standardizedFileURL.path))
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
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-capacity-rollback-store-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settingsWithLimit = BacktraceDatabaseSettings()
                    settingsWithLimit.maxRecordCount = 1
                    let failureLock = NSLock()
                    var shouldFailSave = false
                    var limitedRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        limitedRepository?.shutdownForNativeBridge()
                        limitedRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    limitedRepository = try PersistentRepository<BacktraceReport>(
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
                        },
                        maintenanceRetryDelay: .seconds(60),
                        storeDirectoryUrl: storeDirectory
                    )

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
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-database-size-limit-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settingsWithSizeLimit = BacktraceDatabaseSettings()
                    settingsWithSizeLimit.maxDatabaseSize = 1
                    let sizeLock = NSLock()
                    var exceedsLimit = false
                    var sizeLimitedRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        sizeLimitedRepository?.shutdownForNativeBridge()
                        sizeLimitedRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    sizeLimitedRepository = try PersistentRepository<BacktraceReport>(
                        settings: settingsWithSizeLimit,
                        startupReconciliation: { _ in },
                        databaseSize: { _ in
                            sizeLock.lock()
                            defer { sizeLock.unlock() }
                            return exceedsLimit ? 2 * 1024 * 1024 : 0
                        },
                        maintenanceRetryDelay: .seconds(60),
                        storeDirectoryUrl: storeDirectory
                    )

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

                for capacityName in ["record count", "database size"] {
                    for retryBehaviour in [RetryBehaviour.none, .interval] {
                        let retryName = retryBehaviour == .none ? "none" : "interval"
                        for statusCode in [200, 503] {
                            throwingIt(
                                "admits one protected initial report with \(capacityName), "
                                    + "\(retryName) retry, and HTTP \(statusCode)"
                            ) {
                                let storeDirectory = FileManager.default.temporaryDirectory
                                    .appendingPathComponent(
                                        "backtrace-initial-capacity-admission-\(UUID().uuidString)",
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
                                settings.retryBehaviour = retryBehaviour
                                if capacityName == "database size" {
                                    settings.maxDatabaseSize = 1
                                } else {
                                    settings.maxRecordCount = 1
                                }
                                let sizeLock = NSLock()
                                var exceedsDatabaseLimit = false
                                var limitedRepository: PersistentRepository<BacktraceReport>!
                                defer {
                                    limitedRepository?.shutdownForNativeBridge()
                                    limitedRepository = nil
                                    try? FileManager.default.removeItem(at: storeDirectory)
                                }
                                limitedRepository = try PersistentRepository<BacktraceReport>(
                                    settings: settings,
                                    startupReconciliation: { _ in },
                                    databaseSize: { _ in
                                        sizeLock.lock()
                                        defer { sizeLock.unlock() }
                                        return exceedsDatabaseLimit ? 2 * 1024 * 1024 : 0
                                    },
                                    maintenanceRetryDelay: .seconds(60),
                                    storeDirectoryUrl: storeDirectory
                                )

                                let pendingSource = sourceDirectory.appendingPathComponent("pending.txt")
                                try Data("pending attachment".utf8).write(to: pendingSource)
                                let pending = try BacktraceReport(
                                    pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                                    attributes: ["capacity": "initial"],
                                    attachmentPaths: [pendingSource.path]
                                )
                                expect(try limitedRepository.savePending(pending))
                                    .to(equal(.awaitingSourcePurge))
                                try limitedRepository.promoteAfterSourcePurge(pending)
                                let pendingAttachment = try XCTUnwrap(
                                    limitedRepository.getAll().first?.attachmentPaths.first
                                )

                                sizeLock.lock()
                                exceedsDatabaseLimit = true
                                sizeLock.unlock()
                                let incomingRetry = try crashReporter.generateLiveReport(
                                    attributes: ["capacity": "incoming-retry"]
                                )
                                try limitedRepository.save(incomingRetry)
                                try limitedRepository.reconcileStorage()

                                expect(try limitedRepository.getAll().map(\.identifier))
                                    .to(equal([pending.identifier]))
                                expect(try limitedRepository.persistedState(for: pending))
                                    .to(equal(.readyForInitialSubmission))
                                expect(FileManager.default.fileExists(atPath: pendingAttachment)).to(beTrue())

                                // Keep the failed initial row observable until this test explicitly makes it
                                // eligible for capacity eviction below.
                                sizeLock.lock()
                                exceedsDatabaseLimit = false
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
                                var watcher: BacktraceWatcher<PersistentRepository<BacktraceReport>>?
                                watcher = BacktraceWatcher(
                                    settings: settings,
                                    api: api,
                                    repository: limitedRepository,
                                    networkAvailabilityCheck: { true }
                                )

                                watcher?.drainInitialSubmissions(bypassesReachabilityPreflight: true)
                                watcher?.shutdown()
                                watcher = nil

                                expect(session.requestCount).to(equal(1))
                                expect(try limitedRepository.getInitialSubmission(count: 1)).to(beEmpty())

                                if statusCode == 200 {
                                    expect(try limitedRepository.countResources()).to(equal(0))
                                    expect(FileManager.default.fileExists(atPath: pendingAttachment)).to(beFalse())
                                } else {
                                    expect(try limitedRepository.persistedState(for: pending))
                                        .to(equal(.readyForRetry))
                                    expect(try limitedRepository.getLatest().map(\.identifier))
                                        .to(equal([pending.identifier]))
                                    expect(FileManager.default.fileExists(atPath: pendingAttachment)).to(beTrue())

                                    if capacityName == "database size" {
                                        sizeLock.lock()
                                        exceedsDatabaseLimit = true
                                        sizeLock.unlock()
                                        try limitedRepository.reconcileStorage()
                                        expect(try limitedRepository.countResources()).to(equal(0))
                                    } else {
                                        let laterRetry = try crashReporter.generateLiveReport(
                                            attributes: ["capacity": "later-retry"]
                                        )
                                        try limitedRepository.save(laterRetry)
                                        expect(try limitedRepository.getAll().map(\.identifier))
                                            .to(equal([laterRetry.identifier]))
                                    }
                                    expect(FileManager.default.fileExists(atPath: pendingAttachment)).to(beFalse())
                                }
                            }
                        }
                    }
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
                                var limitedRepository: PersistentRepository<BacktraceReport>!
                                defer {
                                    limitedRepository?.shutdownForNativeBridge()
                                    limitedRepository = nil
                                    try? FileManager.default.removeItem(at: storeDirectory)
                                }
                                limitedRepository = try PersistentRepository<BacktraceReport>(
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
                                        guard try limitedRepository.claimRetrySubmission(overflow) != nil else {
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
                                var coordinator: BacktraceSubmissionCoordinator<
                                    PersistentRepository<BacktraceReport>
                                >? = BacktraceSubmissionCoordinator(
                                    api: api,
                                    repository: limitedRepository,
                                    retryLimit: 3
                                )

                                let receipt = try XCTUnwrap(coordinator).submit(active, origin: origin)
                                coordinator = nil

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

                throwingIt("reconciles database growth after replacing an existing initial row") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-replacement-growth-capacity-\(UUID().uuidString)",
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
                    let sizeLock = NSLock()
                    var exceedsDatabaseLimit = false
                    var growthRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        growthRepository?.shutdownForNativeBridge()
                        growthRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    growthRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        databaseSize: { _ in
                            sizeLock.lock()
                            defer { sizeLock.unlock() }
                            return exceedsDatabaseLimit ? 2 * 1024 * 1024 : 0
                        },
                        maintenanceRetryDelay: .milliseconds(10),
                        storeDirectoryUrl: storeDirectory,
                        deliveryOwnerIsAlive: { _ in true }
                    )

                    let initialPayload = try crashReporter
                        .generateLiveReport(attributes: ["payload": "original"]).reportData
                    let replacementPayload = try crashReporter.generateLiveReport(
                        exception: NSException(
                            name: .genericException,
                            reason: String(repeating: "replacement payload growth ", count: 2_048),
                            userInfo: nil
                        ),
                        attributes: ["payload": "replacement"]
                    ).reportData
                    expect(replacementPayload.count).to(beGreaterThan(initialPayload.count))
                    let initialIdentifier = UUID()
                    let initialOriginal = try BacktraceReport(
                        report: initialPayload,
                        attributes: ["growth": "original"],
                        attachmentPaths: [],
                        identifier: initialIdentifier
                    )
                    let replacementSource = sourceDirectory.appendingPathComponent("replacement.txt")
                    try Data("replacement attachment".utf8).write(to: replacementSource)
                    let initialReplacement = try BacktraceReport(
                        report: replacementPayload,
                        attributes: ["growth": "replacement"],
                        attachmentPaths: [replacementSource.path],
                        identifier: initialIdentifier
                    )
                    let sourceHandoff = try BacktraceReport(
                        pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["growth": "source-handoff"],
                        attachmentPaths: []
                    )
                    let inFlight = try crashReporter.generateLiveReport(
                        attributes: ["growth": "in-flight"]
                    )
                    let safeVictim = try crashReporter.generateLiveReport(
                        attributes: ["growth": "safe-retry-victim"]
                    )

                    // Build the mixed-state repository while capacity is unlimited, so the only
                    // maintenance request below must come from replacing an existing identifier.
                    expect(try growthRepository.savePending(sourceHandoff))
                        .to(equal(.awaitingSourcePurge))
                    expect(try growthRepository.savePending(initialOriginal))
                        .to(equal(.awaitingSourcePurge))
                    try growthRepository.promoteAfterSourcePurge(initialOriginal)
                    try growthRepository.save(inFlight)
                    expect(try growthRepository.claimRetrySubmission(inFlight)).toNot(beNil())
                    try growthRepository.save(safeVictim)
                    expect(try growthRepository.countResources()).to(equal(4))

                    settings.maxDatabaseSize = 1
                    sizeLock.lock()
                    exceedsDatabaseLimit = true
                    sizeLock.unlock()

                    expect(try growthRepository.savePending(initialReplacement))
                        .to(equal(.alreadyOwned(.readyForInitialSubmission)))

                    expect { try growthRepository.countResources() }.toEventually(
                        equal(3),
                        timeout: .seconds(2)
                    )
                    let remainingIdentifiers = Set(try growthRepository.getAll().map(\.identifier))
                    expect(remainingIdentifiers).to(contain(
                        sourceHandoff.identifier,
                        initialIdentifier,
                        inFlight.identifier
                    ))
                    expect(remainingIdentifiers).notTo(contain(safeVictim.identifier))
                    expect(try growthRepository.persistedState(for: sourceHandoff))
                        .to(equal(.awaitingSourcePurge))
                    expect(try growthRepository.persistedState(for: initialReplacement))
                        .to(equal(.readyForInitialSubmission))
                    expect(try growthRepository.persistedState(for: inFlight))
                        .to(equal(.retryInFlight))

                    let storedReplacement = try XCTUnwrap(
                        growthRepository.getAll().first {
                            $0.identifier == initialIdentifier
                        }
                    )
                    let replacementAttachment = try XCTUnwrap(
                        storedReplacement.attachmentPaths.first
                    )
                    expect(storedReplacement.attributes["growth"] as? String)
                        .to(equal("replacement"))
                    expect(storedReplacement.reportData).to(equal(replacementPayload))
                    expect(storedReplacement.reportData).notTo(equal(initialPayload))
                    expect(try Data(contentsOf: URL(fileURLWithPath: replacementAttachment)))
                        .to(equal(Data("replacement attachment".utf8)))
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
                    var recoveringRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        recoveringRepository?.shutdownForNativeBridge()
                        recoveringRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    recoveringRepository = try PersistentRepository<BacktraceReport>(
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
                    let abandoned = try crashReporter.generateLiveReport(attributes: ["capacity": "abandoned"])
                    let survivor = try crashReporter.generateLiveReport(attributes: ["capacity": "survivor"])
                    try recoveringRepository.save(abandoned)
                    expect(try recoveringRepository.claimRetrySubmission(abandoned)).toNot(beNil())
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
                    var overflowRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        overflowRepository?.shutdownForNativeBridge()
                        overflowRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    overflowRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        maintenanceRetryDelay: .milliseconds(50),
                        storeDirectoryUrl: storeDirectory,
                        deliveryOwnerToken: "insert-overflow-owner",
                        deliveryOwnerIsAlive: { _ in true }
                    )
                    let protected = try crashReporter.generateLiveReport(attributes: ["capacity": "protected"])
                    let overflow = try crashReporter.generateLiveReport(attributes: ["capacity": "overflow"])
                    try overflowRepository.save(protected)
                    expect(try overflowRepository.claimRetrySubmission(protected)).toNot(beNil())
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

                throwingIt("keeps bulk-promoted initial reports protected until admission") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-bulk-promotion-capacity-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settings = BacktraceDatabaseSettings()
                    settings.maxRecordCount = 1
                    var promotionRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        promotionRepository?.shutdownForNativeBridge()
                        promotionRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    promotionRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        maintenanceRetryDelay: .milliseconds(10),
                        storeDirectoryUrl: storeDirectory
                    )
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
                    try promotionRepository.reconcileStorage()

                    expect(try promotionRepository.countResources()).to(equal(2))
                    expect(Set(try promotionRepository.getAll().map(\.identifier)))
                        .to(equal(Set([first.identifier, second.identifier])))
                    expect(try promotionRepository.persistedState(for: first))
                        .to(equal(.readyForInitialSubmission))
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
                    var coalescingRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        coalescingRepository?.shutdownForNativeBridge()
                        coalescingRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    coalescingRepository = try PersistentRepository<BacktraceReport>(
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
                    let reports = try (0..<3).map { index in
                        try crashReporter.generateLiveReport(attributes: ["capacity": index])
                    }
                    for report in reports {
                        try coalescingRepository.save(report)
                        expect(try coalescingRepository.claimRetrySubmission(report)).toNot(beNil())
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
                        overlappingRepository?.shutdownForNativeBridge()
                        overlappingRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let firstReport = try crashReporter.generateLiveReport(attributes: ["capacity": "first"])
                    secondReport = try crashReporter.generateLiveReport(attributes: ["capacity": "second"])
                    try overlappingRepository.save(firstReport)
                    try overlappingRepository.save(secondReport)
                    expect(try overlappingRepository.claimRetrySubmission(firstReport)).toNot(beNil())
                    expect(try overlappingRepository.claimRetrySubmission(secondReport)).toNot(beNil())

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
                    let settings = BacktraceDatabaseSettings()
                    settings.maxRecordCount = 3
                    var rankedRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        rankedRepository?.shutdownForNativeBridge()
                        rankedRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    rankedRepository = try PersistentRepository<BacktraceReport>(
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

                throwingIt("quarantines a corrupt initial row and continues to the next valid report") {
                    try repository.clear()
                    let corrupt = try BacktraceReport(
                        pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["row": "corrupt-initial"],
                        attachmentPaths: []
                    )
                    let valid = try BacktraceReport(
                        pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["row": "valid-initial"],
                        attachmentPaths: []
                    )
                    try repository.savePending(corrupt)
                    try repository.promoteAfterSourcePurge(corrupt)
                    try repository.savePending(valid)
                    try repository.promoteAfterSourcePurge(valid)
                    let corruptPendingMetadataUrl = repository.metadataDirectoryUrl
                        .appendingPathComponent("PendingMetadata", isDirectory: true)
                        .appendingPathComponent(corrupt.identifier.uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(
                        at: corruptPendingMetadataUrl,
                        withIntermediateDirectories: true
                    )
                    try Data("pending metadata".utf8).write(
                        to: corruptPendingMetadataUrl.appendingPathComponent("state.plist")
                    )
                    let invalidPayload = Data("invalid-plcrash-payload".utf8)
                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(entityName: BacktraceReport.entityName)
                        request.predicate = NSPredicate(
                            format: "hashProperty == %@",
                            corrupt.identifier.uuidString
                        )
                        let object = try XCTUnwrap(repository.backgroundContext.fetch(request).first)
                        object.setValue(invalidPayload, forKey: "reportData")
                        try repository.backgroundContext.save()
                    }

                    let page = try repository.getInitialSubmission(count: 1)

                    expect(page.map(\.identifier)).to(equal([valid.identifier]))
                    expect(try repository.claimInitialSubmission(valid)?.identifier)
                        .to(equal(valid.identifier))
                    expect(try repository.getInitialSubmission(count: 1)).to(beEmpty())
                    expect(try repository.countResources()).to(equal(1))
                    let archiveRoot = repository.metadataDirectoryUrl
                        .appendingPathComponent("PersistedRowDeadLetters", isDirectory: true)
                    let archiveDirectories = try FileManager.default.contentsOfDirectory(
                        at: archiveRoot,
                        includingPropertiesForKeys: nil
                    )
                    let corruptArchive = try XCTUnwrap(archiveDirectories.first { directory in
                        (try? Data(contentsOf: directory
                            .appendingPathComponent("payload.plcrash", isDirectory: false))) ==
                                invalidPayload
                    })
                    expect(FileManager.default.fileExists(atPath: corruptArchive
                        .appendingPathComponent("attributes.plist", isDirectory: false).path))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: corruptArchive
                        .appendingPathComponent("pending-metadata", isDirectory: true).path))
                        .to(beTrue())
                }

                throwingIt("preserves survivor files when a corrupt row collides with its identifier") {
                    try repository.clear()
                    let corruptAttachmentSource = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-corrupt-collision-\(UUID().uuidString).txt",
                            isDirectory: false
                        )
                    let survivorAttachmentSource = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-survivor-collision-\(UUID().uuidString).txt",
                            isDirectory: false
                        )
                    try Data("corrupt attachment".utf8).write(to: corruptAttachmentSource)
                    try Data("survivor attachment".utf8).write(to: survivorAttachmentSource)
                    defer {
                        try? FileManager.default.removeItem(at: corruptAttachmentSource)
                        try? FileManager.default.removeItem(at: survivorAttachmentSource)
                    }

                    let corrupt = try crashReporter.generateLiveReport(
                        attributes: ["row": "corrupt-collision"],
                        attachmentPaths: [corruptAttachmentSource.path]
                    )
                    let survivor = try crashReporter.generateLiveReport(
                        attributes: ["row": "survivor-collision"],
                        attachmentPaths: [survivorAttachmentSource.path]
                    )
                    try repository.save(corrupt)
                    try repository.save(survivor)

                    let persisted = try repository.getAll()
                    let corruptAttachmentPath = try XCTUnwrap(
                        persisted.first { $0.identifier == corrupt.identifier }?.attachmentPaths.first
                    )
                    let survivorAttachmentPath = try XCTUnwrap(
                        persisted.first { $0.identifier == survivor.identifier }?.attachmentPaths.first
                    )
                    let survivorAttributesUrl = repository.metadataDirectoryUrl
                        .appendingPathComponent("\(survivor.identifier.uuidString).plist")
                    let survivorPendingMetadataUrl = repository.metadataDirectoryUrl
                        .appendingPathComponent("PendingMetadata", isDirectory: true)
                        .appendingPathComponent(survivor.identifier.uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(
                        at: survivorPendingMetadataUrl,
                        withIntermediateDirectories: true
                    )
                    try Data("survivor pending metadata".utf8).write(
                        to: survivorPendingMetadataUrl.appendingPathComponent("state.plist")
                    )

                    let invalidPayload = Data("invalid-colliding-plcrash".utf8)
                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(
                            entityName: BacktraceReport.entityName
                        )
                        let objects = try repository.backgroundContext.fetch(request)
                        let corruptObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "hashProperty") as? String) ==
                                corrupt.identifier.uuidString
                        })
                        corruptObject.setValue(
                            survivor.identifier.uuidString,
                            forKey: "hashProperty"
                        )
                        corruptObject.setValue(invalidPayload, forKey: "reportData")
                        corruptObject.setValue(Date.distantPast, forKey: "dateAdded")
                        let survivorObject = try XCTUnwrap(objects.first {
                            $0.objectID != corruptObject.objectID &&
                                ($0.value(forKey: "hashProperty") as? String) ==
                                    survivor.identifier.uuidString
                        })
                        survivorObject.setValue(Date.distantFuture, forKey: "dateAdded")
                        try repository.backgroundContext.save()
                    }

                    let page = try repository.getOldest(count: 1)

                    expect(page.map(\.identifier)).to(equal([survivor.identifier]))
                    expect(page.first?.attributes["row"] as? String)
                        .to(equal("survivor-collision"))
                    expect(page.first?.attachmentPaths).to(equal([survivorAttachmentPath]))
                    expect(FileManager.default.fileExists(atPath: survivorAttributesUrl.path))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: survivorAttachmentPath))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: survivorPendingMetadataUrl.path))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: corruptAttachmentPath))
                        .to(beFalse())
                    expect(try repository.claimRetrySubmission(try XCTUnwrap(page.first))?.identifier)
                        .to(equal(survivor.identifier))

                    let archiveRoot = repository.metadataDirectoryUrl
                        .appendingPathComponent("PersistedRowDeadLetters", isDirectory: true)
                    let archivedPayloads = try FileManager.default.contentsOfDirectory(
                        at: archiveRoot,
                        includingPropertiesForKeys: nil
                    ).compactMap { directory in
                        try? Data(contentsOf: directory
                            .appendingPathComponent("payload.plcrash", isDirectory: false))
                    }
                    expect(archivedPayloads).to(contain(invalidPayload))
                }

                throwingIt("claims the exact survivor when a later corrupt row shares its identifier") {
                    try repository.clear()
                    let corrupt = try crashReporter.generateLiveReport(
                        attributes: ["claimCollision": "corrupt"]
                    )
                    let survivor = try crashReporter.generateLiveReport(
                        attributes: ["claimCollision": "survivor"]
                    )
                    try repository.save(corrupt)
                    try repository.save(survivor)
                    let invalidPayload = Data("invalid-later-collision".utf8)
                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(
                            entityName: BacktraceReport.entityName
                        )
                        let objects = try repository.backgroundContext.fetch(request)
                        let corruptObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "hashProperty") as? String) ==
                                corrupt.identifier.uuidString
                        })
                        let survivorObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "hashProperty") as? String) ==
                                survivor.identifier.uuidString
                        })
                        corruptObject.setValue(
                            survivor.identifier.uuidString,
                            forKey: "hashProperty"
                        )
                        corruptObject.setValue(invalidPayload, forKey: "reportData")
                        corruptObject.setValue(Date.distantFuture, forKey: "dateAdded")
                        survivorObject.setValue(Date.distantPast, forKey: "dateAdded")
                        try repository.backgroundContext.save()
                    }

                    let page = try repository.getOldest(count: 1)
                    let fetchedSurvivor = try XCTUnwrap(page.first)

                    expect(page.map(\.identifier)).to(equal([survivor.identifier]))
                    expect(fetchedSurvivor.reportData).to(equal(survivor.reportData))
                    expect(fetchedSurvivor.persistedObjectURI).notTo(beNil())
                    let claimed = try repository.claimRetrySubmission(fetchedSurvivor)
                    expect(claimed?.reportData).to(equal(survivor.reportData))
                    expect(claimed?.identifier).to(equal(survivor.identifier))
                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(
                            entityName: BacktraceReport.entityName
                        )
                        let objects = try repository.backgroundContext.fetch(request)
                        let claimedObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "reportData") as? Data) == survivor.reportData
                        })
                        let corruptObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "reportData") as? Data) == invalidPayload
                        })
                        expect((claimedObject.value(forKey: "deliveryStateRaw") as? NSNumber)?.int16Value)
                            .to(equal(PersistedReportState.retryInFlight.rawValue))
                        expect((corruptObject.value(forKey: "deliveryStateRaw") as? NSNumber)?.int16Value)
                            .to(equal(PersistedReportState.readyForRetry.rawValue))
                    }

                    expect(try repository.getOldest(count: 1)).to(beEmpty())
                    expect(try repository.countResources()).to(equal(1))
                    let archiveRoot = repository.metadataDirectoryUrl
                        .appendingPathComponent("PersistedRowDeadLetters", isDirectory: true)
                    let archivedPayloads = try FileManager.default.contentsOfDirectory(
                        at: archiveRoot,
                        includingPropertiesForKeys: nil
                    ).compactMap { directory in
                        try? Data(contentsOf: directory
                            .appendingPathComponent("payload.plcrash", isDirectory: false))
                    }
                    expect(archivedPayloads).to(contain(invalidPayload))
                }

                throwingIt("claims an initial row whose persisted UUID uses lowercase characters") {
                    try repository.clear()
                    let pending = try crashReporter.generateLiveReport(
                        attributes: ["identifierCase": "lowercase"]
                    )
                    expect(try repository.savePending(pending)).to(equal(.awaitingSourcePurge))
                    try repository.promoteAfterSourcePurge(pending)

                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(
                            entityName: BacktraceReport.entityName
                        )
                        let object = try XCTUnwrap(
                            repository.backgroundContext.fetch(request).first
                        )
                        object.setValue(
                            pending.identifier.uuidString.lowercased(),
                            forKey: "hashProperty"
                        )
                        try repository.backgroundContext.save()
                    }

                    let fetched = try XCTUnwrap(
                        repository.getInitialSubmission(count: 1).first
                    )
                    expect(fetched.identifier).to(equal(pending.identifier))
                    expect(fetched.persistedObjectURI).notTo(beNil())
                    let claimed = try repository.claimInitialSubmission(fetched)
                    expect(claimed?.identifier).to(equal(pending.identifier))
                    expect(try repository.persistedState(for: try XCTUnwrap(claimed)))
                        .to(equal(.initialSubmissionInFlight))
                }

                throwingIt("deletes only the exact terminal row when identifiers collide") {
                    try repository.clear()
                    let colliding = try crashReporter.generateLiveReport(
                        attributes: ["terminalCollision": "remaining"]
                    )
                    let terminal = try crashReporter.generateLiveReport(
                        attributes: ["terminalCollision": "deleted"]
                    )
                    try repository.save(colliding)
                    try repository.save(terminal)

                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(
                            entityName: BacktraceReport.entityName
                        )
                        let objects = try repository.backgroundContext.fetch(request)
                        let collidingObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "reportData") as? Data) == colliding.reportData
                        })
                        let terminalObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "reportData") as? Data) == terminal.reportData
                        })
                        collidingObject.setValue(
                            terminal.identifier.uuidString,
                            forKey: "hashProperty"
                        )
                        collidingObject.setValue(Date.distantFuture, forKey: "dateAdded")
                        terminalObject.setValue(Date.distantPast, forKey: "dateAdded")
                        try repository.backgroundContext.save()
                    }

                    let fetchedTerminal = try XCTUnwrap(repository.getOldest(count: 1).first)
                    expect(fetchedTerminal.reportData).to(equal(terminal.reportData))
                    let claimedTerminal = try XCTUnwrap(
                        repository.claimRetrySubmission(fetchedTerminal)
                    )
                    try repository.markTerminalForDeletion(claimedTerminal)
                    try repository.delete(claimedTerminal)

                    expect(try repository.countResources()).to(equal(1))
                    let remaining = try XCTUnwrap(repository.getAll().first)
                    expect(remaining.reportData).to(equal(colliding.reportData))
                    expect(remaining.identifier).to(equal(terminal.identifier))
                    expect(try repository.persistedState(for: remaining))
                        .to(equal(.readyForRetry))
                }

                throwingIt("preserves survivor files when terminal cleanup removes a colliding row") {
                    try repository.clear()
                    let corruptSource = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-terminal-collision-corrupt-\(UUID().uuidString).txt"
                        )
                    let survivorSource = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-terminal-collision-survivor-\(UUID().uuidString).txt"
                        )
                    try Data("terminal corrupt".utf8).write(to: corruptSource)
                    try Data("terminal survivor".utf8).write(to: survivorSource)
                    defer {
                        try? FileManager.default.removeItem(at: corruptSource)
                        try? FileManager.default.removeItem(at: survivorSource)
                    }

                    let corrupt = try crashReporter.generateLiveReport(
                        attributes: ["terminalCollision": "corrupt"],
                        attachmentPaths: [corruptSource.path]
                    )
                    let survivor = try crashReporter.generateLiveReport(
                        attributes: ["terminalCollision": "survivor"],
                        attachmentPaths: [survivorSource.path]
                    )
                    try repository.save(corrupt)
                    try repository.save(survivor)
                    let persisted = try repository.getAll()
                    let corruptAttachmentPath = try XCTUnwrap(
                        persisted.first { $0.identifier == corrupt.identifier }?.attachmentPaths.first
                    )
                    let survivorAttachmentPath = try XCTUnwrap(
                        persisted.first { $0.identifier == survivor.identifier }?.attachmentPaths.first
                    )
                    let survivorAttributesUrl = repository.metadataDirectoryUrl
                        .appendingPathComponent("\(survivor.identifier.uuidString).plist")
                    let survivorPendingMetadataUrl = repository.metadataDirectoryUrl
                        .appendingPathComponent("PendingMetadata", isDirectory: true)
                        .appendingPathComponent(survivor.identifier.uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(
                        at: survivorPendingMetadataUrl,
                        withIntermediateDirectories: true
                    )
                    try Data("terminal pending metadata".utf8).write(
                        to: survivorPendingMetadataUrl.appendingPathComponent("state.plist")
                    )

                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(
                            entityName: BacktraceReport.entityName
                        )
                        let objects = try repository.backgroundContext.fetch(request)
                        let corruptObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "hashProperty") as? String) ==
                                corrupt.identifier.uuidString
                        })
                        corruptObject.setValue(
                            survivor.identifier.uuidString,
                            forKey: "hashProperty"
                        )
                        corruptObject.setValue(
                            NSNumber(value: PersistedReportState.terminalAwaitingDeletion.rawValue),
                            forKey: "deliveryStateRaw"
                        )
                        try repository.backgroundContext.save()
                    }

                    try repository.reconcileStorage()

                    let remaining = try repository.getAll()
                    expect(remaining.map(\.identifier)).to(equal([survivor.identifier]))
                    expect(FileManager.default.fileExists(atPath: survivorAttributesUrl.path))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: survivorAttachmentPath))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: survivorPendingMetadataUrl.path))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: corruptAttachmentPath))
                        .to(beFalse())
                    expect(try repository.claimRetrySubmission(try XCTUnwrap(remaining.first))?.identifier)
                        .to(equal(survivor.identifier))
                }

                throwingIt("preserves a cross-identifier attachment referenced by a surviving row") {
                    try repository.clear()
                    let terminalSource = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-terminal-alias-owner-\(UUID().uuidString).txt"
                        )
                    let survivorSource = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-terminal-alias-survivor-\(UUID().uuidString).txt"
                        )
                    try Data("terminal attachment".utf8).write(to: terminalSource)
                    try Data("survivor attachment".utf8).write(to: survivorSource)
                    defer {
                        try? FileManager.default.removeItem(at: terminalSource)
                        try? FileManager.default.removeItem(at: survivorSource)
                    }

                    let terminal = try crashReporter.generateLiveReport(
                        attributes: ["attachmentAlias": "terminal"],
                        attachmentPaths: [terminalSource.path]
                    )
                    let survivor = try crashReporter.generateLiveReport(
                        attributes: ["attachmentAlias": "survivor"],
                        attachmentPaths: [survivorSource.path]
                    )
                    try repository.save(terminal)
                    try repository.save(survivor)

                    let persisted = try repository.getAll()
                    let terminalAttachmentPath = try XCTUnwrap(
                        persisted.first { $0.identifier == terminal.identifier }?.attachmentPaths.first
                    )
                    let originalSurvivorAttachmentPath = try XCTUnwrap(
                        persisted.first { $0.identifier == survivor.identifier }?.attachmentPaths.first
                    )

                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(
                            entityName: BacktraceReport.entityName
                        )
                        let objects = try repository.backgroundContext.fetch(request)
                        let terminalObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "hashProperty") as? String) ==
                                terminal.identifier.uuidString
                        })
                        let survivorObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "hashProperty") as? String) ==
                                survivor.identifier.uuidString
                        })
                        terminalObject.setValue(
                            NSNumber(value: PersistedReportState.terminalAwaitingDeletion.rawValue),
                            forKey: "deliveryStateRaw"
                        )
                        // Simulate a damaged transformable reference that points into a
                        // generation owned by a different row identifier.
                        survivorObject.setValue(
                            [terminalAttachmentPath],
                            forKey: "attachmentPaths"
                        )
                        try repository.backgroundContext.save()
                    }

                    try repository.reconcileStorage()

                    let remaining = try repository.getAll()
                    let persistedSurvivor = try XCTUnwrap(remaining.first)
                    expect(remaining.map(\.identifier)).to(equal([survivor.identifier]))
                    expect(persistedSurvivor.attachmentPaths).to(equal([terminalAttachmentPath]))
                    expect(FileManager.default.fileExists(atPath: terminalAttachmentPath))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: originalSurvivorAttachmentPath))
                        .to(beFalse())
                    expect(try repository.claimRetrySubmission(persistedSurvivor)?.identifier)
                        .to(equal(survivor.identifier))
                }

                throwingIt("preserves survivor files when capacity evicts a colliding row") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-capacity-collision-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settings = BacktraceDatabaseSettings()
                    settings.maxRecordCount = 2
                    var limitedRepository: PersistentRepository<BacktraceReport>? =
                        try PersistentRepository<BacktraceReport>(
                            settings: settings,
                            startupReconciliation: { _ in },
                            storeDirectoryUrl: storeDirectory
                        )
                    defer {
                        limitedRepository?.shutdownForNativeBridge()
                        limitedRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let corruptSource = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-capacity-collision-corrupt-\(UUID().uuidString).txt"
                        )
                    let survivorSource = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-capacity-collision-survivor-\(UUID().uuidString).txt"
                        )
                    try Data("capacity corrupt".utf8).write(to: corruptSource)
                    try Data("capacity survivor".utf8).write(to: survivorSource)
                    defer {
                        try? FileManager.default.removeItem(at: corruptSource)
                        try? FileManager.default.removeItem(at: survivorSource)
                    }

                    let corrupt = try crashReporter.generateLiveReport(
                        attributes: ["capacityCollision": "corrupt"],
                        attachmentPaths: [corruptSource.path]
                    )
                    let survivor = try crashReporter.generateLiveReport(
                        attributes: ["capacityCollision": "survivor"],
                        attachmentPaths: [survivorSource.path]
                    )
                    let incoming = try crashReporter.generateLiveReport(
                        attributes: ["capacityCollision": "incoming"]
                    )
                    try limitedRepository?.save(corrupt)
                    try limitedRepository?.save(survivor)
                    let persisted = try XCTUnwrap(limitedRepository).getAll()
                    let corruptAttachmentPath = try XCTUnwrap(
                        persisted.first { $0.identifier == corrupt.identifier }?.attachmentPaths.first
                    )
                    let survivorAttachmentPath = try XCTUnwrap(
                        persisted.first { $0.identifier == survivor.identifier }?.attachmentPaths.first
                    )
                    let survivorAttributesUrl = try XCTUnwrap(limitedRepository).metadataDirectoryUrl
                        .appendingPathComponent("\(survivor.identifier.uuidString).plist")
                    let survivorPendingMetadataUrl = try XCTUnwrap(limitedRepository).metadataDirectoryUrl
                        .appendingPathComponent("PendingMetadata", isDirectory: true)
                        .appendingPathComponent(survivor.identifier.uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(
                        at: survivorPendingMetadataUrl,
                        withIntermediateDirectories: true
                    )
                    try Data("capacity pending metadata".utf8).write(
                        to: survivorPendingMetadataUrl.appendingPathComponent("state.plist")
                    )

                    try limitedRepository?.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(
                            entityName: BacktraceReport.entityName
                        )
                        let objects = try limitedRepository?.backgroundContext.fetch(request) ?? []
                        let corruptObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "hashProperty") as? String) ==
                                corrupt.identifier.uuidString
                        })
                        let survivorObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "hashProperty") as? String) ==
                                survivor.identifier.uuidString
                        })
                        corruptObject.setValue(
                            survivor.identifier.uuidString,
                            forKey: "hashProperty"
                        )
                        corruptObject.setValue(Date.distantPast, forKey: "dateAdded")
                        survivorObject.setValue(Date.distantFuture, forKey: "dateAdded")
                        try limitedRepository?.backgroundContext.save()
                    }

                    try limitedRepository?.save(incoming)
                    try limitedRepository?.reconcileStorage()

                    let remaining = try XCTUnwrap(limitedRepository).getAll()
                    expect(Set(remaining.map(\.identifier)))
                        .to(equal(Set([survivor.identifier, incoming.identifier])))
                    expect(FileManager.default.fileExists(atPath: survivorAttributesUrl.path))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: survivorAttachmentPath))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: survivorPendingMetadataUrl.path))
                        .to(beTrue())
                    expect(FileManager.default.fileExists(atPath: corruptAttachmentPath))
                        .to(beFalse())
                    let persistedSurvivor = try XCTUnwrap(remaining.first {
                        $0.identifier == survivor.identifier
                    })
                    expect(try limitedRepository?.claimRetrySubmission(persistedSurvivor)?.identifier)
                        .to(equal(survivor.identifier))
                }

                throwingIt("quarantines malformed retry rows and cleans their owned files") {
                    try repository.clear()
                    let sourceUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-corrupt-row-attachment-\(UUID().uuidString).txt",
                            isDirectory: false
                        )
                    try Data("owned attachment".utf8).write(to: sourceUrl)
                    defer { try? FileManager.default.removeItem(at: sourceUrl) }

                    let invalidIdentifier = try crashReporter.generateLiveReport(
                        attributes: ["row": "invalid-identifier"],
                        attachmentPaths: [sourceUrl.path]
                    )
                    let nilPayload = try crashReporter.generateLiveReport(
                        attributes: ["row": "nil-payload"]
                    )
                    let invalidPayload = try crashReporter.generateLiveReport(
                        attributes: ["row": "invalid-payload"]
                    )
                    let invalidAttachments = try crashReporter.generateLiveReport(
                        attributes: ["row": "invalid-attachments"]
                    )
                    let valid = try crashReporter.generateLiveReport(
                        attributes: ["row": "valid-retry"]
                    )
                    for report in [invalidIdentifier, nilPayload, invalidPayload, invalidAttachments, valid] {
                        try repository.save(report)
                    }
                    let ownedAttachmentPath = try XCTUnwrap(
                        repository.getAll().first {
                            $0.identifier == invalidIdentifier.identifier
                        }?.attachmentPaths.first
                    )
                    let ownedAttributesUrl = repository.metadataDirectoryUrl
                        .appendingPathComponent("\(invalidIdentifier.identifier.uuidString).plist")

                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(entityName: BacktraceReport.entityName)
                        let objects = try repository.backgroundContext.fetch(request)
                        func object(for identifier: UUID) throws -> NSManagedObject {
                            try XCTUnwrap(objects.first {
                                ($0.value(forKey: "hashProperty") as? String) == identifier.uuidString
                            })
                        }
                        try object(for: invalidIdentifier.identifier)
                            .setValue("not-a-report-uuid", forKey: "hashProperty")
                        try object(for: nilPayload.identifier).setValue(nil, forKey: "reportData")
                        try object(for: invalidPayload.identifier)
                            .setValue(Data("not-a-plcrash-report".utf8), forKey: "reportData")
                        try object(for: invalidAttachments.identifier)
                            .setValue([NSNumber(value: 1)], forKey: "attachmentPaths")
                        try repository.backgroundContext.save()
                    }

                    let page = try repository.getOldest(count: 1)

                    expect(page.map(\.identifier)).to(equal([valid.identifier]))
                    expect(try repository.claimRetrySubmission(valid)?.identifier)
                        .to(equal(valid.identifier))
                    expect(try repository.getOldest(count: 1)).to(beEmpty())
                    expect(try repository.countResources()).to(equal(1))
                    expect(FileManager.default.fileExists(atPath: ownedAttachmentPath)).to(beFalse())
                    expect(FileManager.default.fileExists(atPath: ownedAttributesUrl.path)).to(beFalse())
                    let archiveRoot = repository.metadataDirectoryUrl
                        .appendingPathComponent("PersistedRowDeadLetters", isDirectory: true)
                    let archives = try FileManager.default.contentsOfDirectory(
                        at: archiveRoot,
                        includingPropertiesForKeys: nil
                    )
                    expect(archives.count).to(beGreaterThanOrEqualTo(4))
                }

                throwingIt("bounds corrupt persisted-row archives") {
                    try repository.clear()
                    let archiveRoot = repository.metadataDirectoryUrl
                        .appendingPathComponent("PersistedRowDeadLetters", isDirectory: true)
                    try? FileManager.default.removeItem(at: archiveRoot)
                    var reports = [BacktraceReport]()
                    for index in 0..<14 {
                        let report = try crashReporter.generateLiveReport(attributes: ["archive": index])
                        try repository.save(report)
                        reports.append(report)
                    }
                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(entityName: BacktraceReport.entityName)
                        for object in try repository.backgroundContext.fetch(request) {
                            let identifier = object.value(forKey: "hashProperty") as? String ?? "unknown"
                            object.setValue(Data("invalid-\(identifier)".utf8), forKey: "reportData")
                        }
                        try repository.backgroundContext.save()
                    }

                    expect(try repository.getLatest(count: reports.count)).to(beEmpty())
                    expect(try repository.countResources()).to(equal(0))
                    let archives = try FileManager.default.contentsOfDirectory(
                        at: archiveRoot,
                        includingPropertiesForKeys: nil
                    )
                    expect(archives.count).to(equal(10))
                }

                throwingIt("keeps distinct archives for corrupt rows with the same identifier") {
                    try repository.clear()
                    let archiveRoot = repository.metadataDirectoryUrl
                        .appendingPathComponent("PersistedRowDeadLetters", isDirectory: true)
                    try? FileManager.default.removeItem(at: archiveRoot)
                    let first = try crashReporter.generateLiveReport(attributes: ["collision": "first"])
                    let second = try crashReporter.generateLiveReport(attributes: ["collision": "second"])
                    try repository.save(first)
                    try repository.save(second)
                    let sharedIdentifier = UUID().uuidString
                    let firstPayload = Data("invalid-collision-first".utf8)
                    let secondPayload = Data("invalid-collision-second".utf8)
                    try repository.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(entityName: BacktraceReport.entityName)
                        let objects = try repository.backgroundContext.fetch(request)
                        let firstObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "hashProperty") as? String) == first.identifier.uuidString
                        })
                        let secondObject = try XCTUnwrap(objects.first {
                            ($0.value(forKey: "hashProperty") as? String) == second.identifier.uuidString
                        })
                        firstObject.setValue(sharedIdentifier, forKey: "hashProperty")
                        firstObject.setValue(firstPayload, forKey: "reportData")
                        secondObject.setValue(sharedIdentifier, forKey: "hashProperty")
                        secondObject.setValue(secondPayload, forKey: "reportData")
                        try repository.backgroundContext.save()
                    }

                    expect(try repository.getLatest(count: 2)).to(beEmpty())
                    let archives = try FileManager.default.contentsOfDirectory(
                        at: archiveRoot,
                        includingPropertiesForKeys: nil
                    )
                    let payloads = archives.compactMap { directory in
                        try? Data(contentsOf: directory
                            .appendingPathComponent("payload.plcrash", isDirectory: false))
                    }
                    expect(archives.count).to(equal(2))
                    expect(payloads).to(contain(firstPayload, secondPayload))
                }

                throwingIt("releases protected capacity after quarantining a corrupt initial row") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-corrupt-protected-capacity-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settings = BacktraceDatabaseSettings()
                    settings.maxRecordCount = 1
                    var limitedRepository: PersistentRepository<BacktraceReport>? =
                        try PersistentRepository<BacktraceReport>(
                            settings: settings,
                            startupReconciliation: { _ in },
                            storeDirectoryUrl: storeDirectory
                        )
                    defer {
                        limitedRepository?.shutdownForNativeBridge()
                        limitedRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let corrupt = try BacktraceReport(
                        pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["capacity": "corrupt"],
                        attachmentPaths: []
                    )
                    let valid = try BacktraceReport(
                        pendingReport: crashReporter.generateLiveReport(attributes: [:]).reportData,
                        attributes: ["capacity": "valid"],
                        attachmentPaths: []
                    )
                    try limitedRepository?.savePending(corrupt)
                    try limitedRepository?.promoteAfterSourcePurge(corrupt)
                    try limitedRepository?.savePending(valid)
                    try limitedRepository?.promoteAfterSourcePurge(valid)
                    try limitedRepository?.backgroundContext.performAndWaitThrowing {
                        let request = NSFetchRequest<NSManagedObject>(entityName: BacktraceReport.entityName)
                        request.predicate = NSPredicate(
                            format: "hashProperty == %@",
                            corrupt.identifier.uuidString
                        )
                        let object = try XCTUnwrap(
                            limitedRepository?.backgroundContext.fetch(request).first
                        )
                        object.setValue(nil, forKey: "reportData")
                        try limitedRepository?.backgroundContext.save()
                    }

                    expect(try limitedRepository?.getInitialSubmission(count: 1).map(\.identifier))
                        .to(equal([valid.identifier]))
                    expect(try limitedRepository?.countResources()).to(equal(1))
                }

                throwingIt("fails closed for an unknown non-null persisted delivery state") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-unknown-delivery-state-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settings = BacktraceDatabaseSettings()
                    settings.maxRecordCount = 1
                    var isolatedRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        isolatedRepository?.shutdownForNativeBridge()
                        isolatedRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    isolatedRepository = try PersistentRepository<BacktraceReport>(
                        settings: settings,
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory
                    )
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
                    expect(try repository.claimInitialSubmission(pending)).toNot(beNil())
                    expect(try repository.claimInitialSubmission(pending)).to(beNil())
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
                    var migratedRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        migratedRepository?.shutdownForNativeBridge()
                        migratedRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }

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

                    migratedRepository = try PersistentRepository<BacktraceReport>(
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
                    var firstRepository: PersistentRepository<BacktraceReport>!
                    var secondRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        firstRepository?.shutdownForNativeBridge()
                        secondRepository?.shutdownForNativeBridge()
                        firstRepository = nil
                        secondRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }
                    firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try firstRepository.save(report)

                    let claims = try [firstRepository, secondRepository].map {
                        try $0.claimRetrySubmission(report)
                    }

                    expect(claims.compactMap { $0 }).to(haveCount(1))
                    expect(try secondRepository.persistedState(for: report)).to(equal(.retryInFlight))
                    try secondRepository.resetInFlightReports()
                    expect(try firstRepository.persistedState(for: report)).to(equal(.readyForRetry))
                }

                throwingIt("releases shared state and file descriptors for distinct repositories") {
                    let repositoryCount = 128
                    let storesRootDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-shared-state-lifetime-\(UUID().uuidString)",
                                              isDirectory: true)
                    try FileManager.default.createDirectory(at: storesRootDirectoryUrl,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: storesRootDirectoryUrl) }
                    let baselineStateCount = PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting
#if canImport(Darwin)
                    let baselineDescriptorCount = openDarwinFileDescriptorCount()
#endif

                    for index in 0..<repositoryCount {
                        let storeDirectoryUrl = storesRootDirectoryUrl
                            .appendingPathComponent("repository-\(index)", isDirectory: true)
                        try autoreleasepool {
                            var repository: PersistentRepository<BacktraceReport>? =
                                try PersistentRepository<BacktraceReport>(
                                    settings: BacktraceDatabaseSettings(),
                                    startupReconciliation: { _ in },
                                    storeDirectoryUrl: storeDirectoryUrl
                                )
                            repository?.shutdownForNativeBridge()
                            repository = nil
                        }
                    }

                    expect(PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting)
                        .to(equal(baselineStateCount))
#if canImport(Darwin)
                    let retainedDescriptorCount = openDarwinFileDescriptorCount() - baselineDescriptorCount
                    expect(retainedDescriptorCount).to(beLessThanOrEqualTo(8))
#endif
                }

                throwingIt("releases native repository state while the disabled client remains retained") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-store-shutdown-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let baselineStateCount =
                        PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting
                    var shutdownRepository: PersistentRepository<BacktraceReport>? =
                        try PersistentRepository<BacktraceReport>(
                            settings: BacktraceDatabaseSettings(),
                            startupReconciliation: { _ in },
                            storeDirectoryUrl: storeDirectoryUrl
                        )
                    var reopenedRepository: PersistentRepository<BacktraceReport>?
                    defer {
                        reopenedRepository?.shutdownForNativeBridge()
                        shutdownRepository?.shutdownForNativeBridge()
                        reopenedRepository = nil
                        shutdownRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }

                    let coordinator = try XCTUnwrap(
                        shutdownRepository?.backgroundContext.persistentStoreCoordinator
                    )
                    expect(shutdownRepository?.sharedStateIdentifierForTesting).notTo(beNil())
                    let originalOwnerToken = try XCTUnwrap(
                        shutdownRepository?.deliveryOwnerTokenForTesting
                    )
                    let leaseUrl = storeDirectoryUrl
                        .appendingPathComponent("BacktraceReportLocks", isDirectory: true)
                        .appendingPathComponent("Leases", isDirectory: true)
                        .appendingPathComponent("\(originalOwnerToken).lock", isDirectory: false)
                    expect(coordinator.persistentStores).to(haveCount(1))
                    expect(PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting)
                        .to(equal(baselineStateCount + 1))
                    expect(FileManager.default.fileExists(atPath: leaseUrl.path)).to(beTrue())

                    shutdownRepository?.shutdownForNativeBridge()

                    expect(coordinator.persistentStores).to(beEmpty())
                    expect(shutdownRepository).notTo(beNil())
                    expect(shutdownRepository?.sharedStateIdentifierForTesting).to(beNil())
                    expect(PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting)
                        .to(equal(baselineStateCount))
                    expect(FileManager.default.fileExists(atPath: leaseUrl.path)).to(beFalse())

                    // A retained, disabled Unity client must not keep the old
                    // process lease alive or prevent a fresh repository generation.
                    reopenedRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    expect(reopenedRepository?.sharedStateIdentifierForTesting).notTo(beNil())
                    expect(reopenedRepository?.deliveryOwnerTokenForTesting)
                        .notTo(equal(originalOwnerToken))
                }

                throwingIt("retains one shared state until the final repository is released") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-shared-state-generation-\(UUID().uuidString)",
                                              isDirectory: true)
                    let baselineStateCount = PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting
                    var firstRepository: PersistentRepository<BacktraceReport>?
                    var secondRepository: PersistentRepository<BacktraceReport>?
                    defer {
                        secondRepository?.shutdownForNativeBridge()
                        firstRepository?.shutdownForNativeBridge()
                        secondRepository = nil
                        firstRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }

                    firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let firstStateIdentifier = try XCTUnwrap(firstRepository?.sharedStateIdentifierForTesting)
                    let ownerToken = try XCTUnwrap(firstRepository?.deliveryOwnerTokenForTesting)
                    let leaseUrl = storeDirectoryUrl
                        .appendingPathComponent("BacktraceReportLocks", isDirectory: true)
                        .appendingPathComponent("Leases", isDirectory: true)
                        .appendingPathComponent("\(ownerToken).lock", isDirectory: false)

                    secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    expect(secondRepository?.sharedStateIdentifierForTesting).to(equal(firstStateIdentifier))
                    expect(secondRepository?.deliveryOwnerTokenForTesting).to(equal(ownerToken))
                    expect(PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting)
                        .to(equal(baselineStateCount + 1))
                    expect(FileManager.default.fileExists(atPath: leaseUrl.path)).to(beTrue())

                    firstRepository?.shutdownForNativeBridge()
                    firstRepository = nil
                    expect(PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting)
                        .to(equal(baselineStateCount + 1))
                    expect(FileManager.default.fileExists(atPath: leaseUrl.path)).to(beTrue())

                    secondRepository?.shutdownForNativeBridge()
                    secondRepository = nil
                    expect(PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting)
                        .to(equal(baselineStateCount))
                    expect(FileManager.default.fileExists(atPath: leaseUrl.path)).to(beFalse())
                }

                throwingIt("reopens a released database with a fresh lease and recovers its old claim") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-shared-state-reopen-\(UUID().uuidString)",
                                              isDirectory: true)
                    let baselineStateCount = PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting
                    var sourceRepository: PersistentRepository<BacktraceReport>?
                    var recoveringRepository: PersistentRepository<BacktraceReport>?
                    defer {
                        recoveringRepository?.shutdownForNativeBridge()
                        sourceRepository?.shutdownForNativeBridge()
                        recoveringRepository = nil
                        sourceRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }

                    sourceRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    try sourceRepository?.recoverStaleInFlightReportsOncePerProcess()
                    let oldOwnerToken = try XCTUnwrap(sourceRepository?.deliveryOwnerTokenForTesting)
                    let oldLeaseUrl = storeDirectoryUrl
                        .appendingPathComponent("BacktraceReportLocks", isDirectory: true)
                        .appendingPathComponent("Leases", isDirectory: true)
                        .appendingPathComponent("\(oldOwnerToken).lock", isDirectory: false)
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try sourceRepository?.save(report)
                    expect(try sourceRepository?.claimRetrySubmission(report)).toNot(beNil())
                    expect(try sourceRepository?.persistedDeliveryOwner(for: report)).to(equal(oldOwnerToken))

                    sourceRepository?.shutdownForNativeBridge()
                    sourceRepository = nil
                    expect(FileManager.default.fileExists(atPath: oldLeaseUrl.path)).to(beFalse())

                    recoveringRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let newOwnerToken = try XCTUnwrap(recoveringRepository?.deliveryOwnerTokenForTesting)
                    expect(newOwnerToken).notTo(equal(oldOwnerToken))
                    let newLeaseUrl = storeDirectoryUrl
                        .appendingPathComponent("BacktraceReportLocks", isDirectory: true)
                        .appendingPathComponent("Leases", isDirectory: true)
                        .appendingPathComponent("\(newOwnerToken).lock", isDirectory: false)

                    try recoveringRepository?.recoverStaleInFlightReportsOncePerProcess()
                    expect(try recoveringRepository?.persistedState(for: report)).to(equal(.readyForRetry))
                    expect(try recoveringRepository?.persistedDeliveryOwner(for: report)).to(beNil())
                    expect(try recoveringRepository?.claimRetrySubmission(report)).toNot(beNil())

                    recoveringRepository?.shutdownForNativeBridge()
                    recoveringRepository = nil
                    expect(PersistentRepository<BacktraceReport>.liveSharedStateCountForTesting)
                        .to(equal(baselineStateCount))
                    expect(FileManager.default.fileExists(atPath: newLeaseUrl.path)).to(beFalse())
                }

                throwingIt("does not rewind a live claim when a second repository performs startup recovery") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-once-per-process-recovery-\(UUID().uuidString)",
                                              isDirectory: true)
                    var firstRepository: PersistentRepository<BacktraceReport>!
                    var secondRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        firstRepository?.shutdownForNativeBridge()
                        secondRepository?.shutdownForNativeBridge()
                        firstRepository = nil
                        secondRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }
                    firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    try firstRepository.recoverStaleInFlightReportsOncePerProcess()
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try firstRepository.save(report)
                    expect(try firstRepository.claimRetrySubmission(report)).toNot(beNil())

                    secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    try secondRepository.recoverStaleInFlightReportsOncePerProcess()

                    expect(try secondRepository.persistedState(for: report)).to(equal(.retryInFlight))
                    expect(try secondRepository.claimRetrySubmission(report)).to(beNil())
                }

                throwingIt("does not recover an in-flight row owned by a live foreign process") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-live-foreign-owner-\(UUID().uuidString)",
                                              isDirectory: true)
                    var foreignRepository: PersistentRepository<BacktraceReport>!
                    var recoveringRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        foreignRepository?.shutdownForNativeBridge()
                        recoveringRepository?.shutdownForNativeBridge()
                        foreignRepository = nil
                        recoveringRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }
                    let foreignOwner = UUID().uuidString
                    foreignRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: foreignOwner
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try foreignRepository.save(report)
                    expect(try foreignRepository.claimRetrySubmission(report)).toNot(beNil())

                    recoveringRepository = try PersistentRepository<BacktraceReport>(
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
                    var foreignRepository: PersistentRepository<BacktraceReport>!
                    var recoveringRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        foreignRepository?.shutdownForNativeBridge()
                        recoveringRepository?.shutdownForNativeBridge()
                        foreignRepository = nil
                        recoveringRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }
                    let foreignOwner = UUID().uuidString
                    foreignRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: foreignOwner
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try foreignRepository.save(report)
                    expect(try foreignRepository.claimRetrySubmission(report)).toNot(beNil())

                    var foreignOwnerIsAlive = true
                    recoveringRepository = try PersistentRepository<BacktraceReport>(
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
                        sourceRepository?.shutdownForNativeBridge()
                        recoveringRepository?.shutdownForNativeBridge()
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
                    expect(try sourceRepository?.claimRetrySubmission(report)).toNot(beNil())

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
                    let initializationGroup = DispatchGroup()
                    let resultLock = NSLock()
                    var initializedRepository: PersistentRepository<BacktraceReport>?
                    var initializationError: Error?
                    var initializationWasJoined = false
                    defer {
                        databaseLockProcess.stop()
                        let cleanupRepository = {
                            resultLock.lock()
                            initializedRepository?.shutdownForNativeBridge()
                            initializedRepository = nil
                            resultLock.unlock()
                            try? FileManager.default.removeItem(at: storeDirectoryUrl)
                        }
                        if initializationWasJoined ||
                            initializationGroup.wait(timeout: .now() + 5) == .success {
                            cleanupRepository()
                        } else {
                            initializationGroup.notify(queue: .global(), execute: cleanupRepository)
                        }
                    }

                    try databaseLockProcess.start()
                    initializationGroup.enter()
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
                        initializationGroup.leave()
                    }

                    expect(initializationFinished.wait(timeout: .now() + .milliseconds(250)))
                        .to(equal(.timedOut))
                    expect(FileManager.default.fileExists(atPath: leaseDirectoryUrl.path)).to(beFalse())

                    databaseLockProcess.stop()
                    let initializationResult = initializationFinished.wait(timeout: .now() + 5)
                    expect(initializationResult).to(equal(.success))
                    if initializationResult == .success {
                        let joinResult = initializationGroup.wait(timeout: .now() + 5)
                        expect(joinResult).to(equal(.success))
                        initializationWasJoined = joinResult == .success
                    }
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
                    var sourceRepository: PersistentRepository<BacktraceReport>!
                    var recoveringRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        sourceRepository?.shutdownForNativeBridge()
                        recoveringRepository?.shutdownForNativeBridge()
                        sourceRepository = nil
                        recoveringRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }
                    let foreignOwner = UUID().uuidString
                    sourceRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: foreignOwner
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try sourceRepository.save(report)
                    expect(try sourceRepository.claimRetrySubmission(report)).toNot(beNil())

                    let ownerLeaseUrl = storeDirectoryUrl
                        .appendingPathComponent("BacktraceReportLocks", isDirectory: true)
                        .appendingPathComponent("Leases", isDirectory: true)
                        .appendingPathComponent("\(foreignOwner).lock", isDirectory: true)
                    try FileManager.default.createDirectory(at: ownerLeaseUrl,
                                                            withIntermediateDirectories: true)
                    recoveringRepository = try PersistentRepository<BacktraceReport>(
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
                    var foreignRepository: PersistentRepository<BacktraceReport>!
                    var recoveringRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        foreignRepository?.shutdownForNativeBridge()
                        recoveringRepository?.shutdownForNativeBridge()
                        foreignRepository = nil
                        recoveringRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }
                    foreignRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl,
                        deliveryOwnerToken: UUID().uuidString
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try foreignRepository.save(report)
                    expect(try foreignRepository.claimRetrySubmission(report)).toNot(beNil())

                    recoveringRepository = try PersistentRepository<BacktraceReport>(
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
                    var sourceRepository: PersistentRepository<BacktraceReport>!
                    var failingRepository: PersistentRepository<BacktraceReport>!
                    var recoveringRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        sourceRepository?.shutdownForNativeBridge()
                        failingRepository?.shutdownForNativeBridge()
                        recoveringRepository?.shutdownForNativeBridge()
                        sourceRepository = nil
                        failingRepository = nil
                        recoveringRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }
                    sourceRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try sourceRepository.save(report)
                    expect(try sourceRepository.claimRetrySubmission(report)).toNot(beNil())

                    failingRepository = try PersistentRepository<BacktraceReport>(
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

                    recoveringRepository = try PersistentRepository<BacktraceReport>(
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
                    var firstRepository: PersistentRepository<BacktraceReport>!
                    var secondRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        firstRepository?.shutdownForNativeBridge()
                        secondRepository?.shutdownForNativeBridge()
                        firstRepository = nil
                        secondRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }
                    firstRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    secondRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectoryUrl
                    )
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try firstRepository.save(report)
                    expect(try firstRepository.claimRetrySubmission(report)).toNot(beNil())

                    try firstRepository.markReadyForRetry(report, incrementRetryCountWithLimit: 3)

                    expect(try secondRepository.claimRetrySubmission(report)).toNot(beNil())
                    try secondRepository.markReadyForRetry(report, incrementRetryCountWithLimit: 0)
                    expect(try firstRepository.countResources()).to(equal(0))
                    expect(try firstRepository.claimRetrySubmission(report)).to(beNil())
                }

                throwingIt("does not reactivate an in-flight row when terminal marking and deletion both fail") {
                    let storeDirectoryUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("backtrace-terminal-failure-\(UUID().uuidString)",
                                              isDirectory: true)
                    var failingRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        failingRepository?.shutdownForNativeBridge()
                        failingRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectoryUrl)
                    }
                    let saveLock = NSLock()
                    var shouldFail = false
                    failingRepository = try PersistentRepository<BacktraceReport>(
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
                    expect(try failingRepository.claimRetrySubmission(report)).toNot(beNil())

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
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-deferred-shutdown-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    var deferredRepository: PersistentRepository<BacktraceReport>? =
                        try PersistentRepository<BacktraceReport>(
                            settings: BacktraceDatabaseSettings(),
                            startupReconciliation: { _ in throw FileError.fileNotWritten },
                            maintenanceRetryDelay: .milliseconds(250),
                            storeDirectoryUrl: storeDirectory
                        )
                    var verificationRepository: PersistentRepository<BacktraceReport>?
                    defer {
                        verificationRepository?.shutdownForNativeBridge()
                        deferredRepository?.shutdownForNativeBridge()
                        verificationRepository = nil
                        deferredRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    try deferredRepository?.save(report)
                    try deferredRepository?.markTerminalForDeletion(report)

                    deferredRepository?.shutdownForNativeBridge()
                    try deferredRepository?.reconcileStorage()
                    Thread.sleep(forTimeInterval: 0.35)

                    expect(deferredRepository?.isShutdown).to(beTrue())
                    verificationRepository = try PersistentRepository<BacktraceReport>(
                        settings: BacktraceDatabaseSettings(),
                        startupReconciliation: { _ in },
                        storeDirectoryUrl: storeDirectory
                    )
                    expect(try verificationRepository?.countResources()).to(equal(1))
                }
                
                throwingIt("test with a custom maxRecordCount, removes oldest records when max record count is exceeded") {
                    let storeDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "backtrace-record-count-limit-\(UUID().uuidString)",
                            isDirectory: true
                        )
                    let settingsWithLimit = BacktraceDatabaseSettings()
                    settingsWithLimit.maxRecordCount = 5
                    var limitedRepository: PersistentRepository<BacktraceReport>!
                    defer {
                        limitedRepository?.shutdownForNativeBridge()
                        limitedRepository = nil
                        try? FileManager.default.removeItem(at: storeDirectory)
                    }
                    limitedRepository = try PersistentRepository<BacktraceReport>(
                        settings: settingsWithLimit,
                        maintenanceRetryDelay: .seconds(60),
                        storeDirectoryUrl: storeDirectory
                    )
                    try limitedRepository.clear()
                    // Insert 6 reports
                    let payload = try crashReporter.generateLiveReport(attributes: [:]).reportData
                    let timeOrderedReports = try (1...6).map { sequence -> BacktraceReport in
                        // PLCrashReporter uses process-global live-report state. Reuse one
                        // validated payload and vary only repository identity so this capacity
                        // test does not depend on six consecutive native captures.
                        let report = try BacktraceReport(
                            report: payload,
                            attributes: ["sequence": sequence],
                            attachmentPaths: [],
                            identifier: UUID()
                        )
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
