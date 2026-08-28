import XCTest

import Nimble
import Quick
@testable import Backtrace

// swiftlint:disable:next type_body_length
final class BacktraceReporterTests: QuickSpec {
    // swiftlint:disable function_body_length force_try
    override func spec() {
        describe("Backtrace reporter") {
            let urlSession = URLSessionMock()
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            var backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
            let delegate = BacktraceClientDelegateSpy()
            var reporter = try! BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                  api: backtraceApi,
                                                  dbSettings: BacktraceDatabaseSettings(),
                                                  credentials: credentials,
                                                  oomMode: .full,
                                                  urlSession: urlSession)

            throwingBeforeEach {
                delegate.clear()
                backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
                reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                 api: backtraceApi,
                                                 dbSettings: BacktraceDatabaseSettings(),
                                                 credentials: credentials,
                                                 oomMode: .full,
                                                 urlSession: urlSession)
                try reporter.repository.clear()
                reporter.delegate = delegate
            }

            context("when native bridge shutdown is requested") {
                it("stops reporter background activity idempotently") {
                    reporter.enableOomWatcher()
                    #if os(macOS)
                    expect(reporter.memoryPressureSource).toNot(beNil())
                    #endif

                    reporter.shutdown()
                    reporter.shutdown()
                    reporter.enableOomWatcher()

                    expect(reporter.isShutdown).to(beTrue())
                    expect(reporter.watcher.isShutdown).to(beTrue())
                    expect(reporter.backtraceOomWatcher.isShutdown).to(beTrue())
                    #if os(macOS)
                    expect(reporter.memoryPressureSource).to(beNil())
                    #endif
                }
            }

            context("given valid HTTP response") {
                it("sends report and calls delegate methods") {
                    urlSession.response = MockOkResponse()
                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.ok))

                    expect { delegate.calledWillSend }.to(beTrue())
                    expect { delegate.calledWillSendRequest }.to(beTrue())
                    expect { delegate.calledServerDidRespond }.to(beTrue())
                    expect { delegate.calledConnectionDidFail }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beFalse())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                    expect { try reporter.repository.countResources() }.to(equal(0))
                }
            }
            context("given no HTTP response") {
                it("sends report and calls delegate methods") {
                    urlSession.response = MockNoResponse()
                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.unknownError))

                    expect { delegate.calledWillSend }.to(beTrue())
                    expect { delegate.calledWillSendRequest }.to(beTrue())
                    expect { delegate.calledConnectionDidFail }.to(beTrue())
                    expect { delegate.calledServerDidRespond }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beFalse())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                    expect { try reporter.repository.countResources() }.to(equal(1))
                }
            }

            context("given connection error") {
                it("fails to send report and calls delegate methods") {
                    urlSession.response =
                        MockConnectionErrorResponse()
                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.unknownError))

                    expect { delegate.calledWillSend }.to(beTrue())
                    expect { delegate.calledWillSendRequest }.to(beTrue())
                    expect { delegate.calledConnectionDidFail }.to(beTrue())
                    expect { delegate.calledServerDidRespond }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beFalse())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                    expect { try reporter.repository.countResources() }.to(equal(1))
                }
            }

            context("given a permanent URL configuration error") {
                it("notifies the delegate without persisting the report") {
                    urlSession.response = MockUrlErrorResponse(.badURL)
                    let result = reporter.send(resource: try reporter.generate())

                    expect(result.backtraceStatus).to(equal(.unknownError))
                    expect(result.submissionDisposition).to(equal(.permanentFailure))
                    expect(delegate.calledWillSend).to(beTrue())
                    expect(delegate.calledWillSendRequest).to(beTrue())
                    expect(delegate.calledConnectionDidFail).to(beTrue())
                    expect(delegate.calledServerDidRespond).to(beFalse())
                    expect(try reporter.repository.countResources()).to(equal(0))
                }
            }

            context("given forbidden HTTP response") {
                it("does not persist a permanently rejected report") {
                    urlSession.response = Mock403Response()
                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.serverError))

                    expect { delegate.calledWillSend }.to(beTrue())
                    expect { delegate.calledWillSendRequest }.to(beTrue())
                    expect { delegate.calledServerDidRespond }.to(beTrue())
                    expect { delegate.calledConnectionDidFail }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beFalse())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                    expect { try reporter.repository.countResources() }.to(equal(0))
                }
            }

            context("given retryable HTTP response") {
                it("persists the report for retry") {
                    urlSession.response = MockHttpResponse(statusCode: 503)

                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.serverError))
                    expect { try reporter.repository.countResources() }.to(equal(1))
                }
            }

            context("given too many reports to send") {
                throwingIt("fails and calls limit reached delegate methods") {
                    backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 1)
                    reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                     api: backtraceApi,
                                                     dbSettings: BacktraceDatabaseSettings(),
                                                     credentials: credentials,
                                                     oomMode: .full,
                                                     urlSession: urlSession)
                    reporter.delegate = delegate

                    urlSession.response = MockOkResponse()
                    _ = try backtraceApi.send(try reporter.generate())
                    delegate.clear()
                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.limitReached))

                    expect { delegate.calledWillSend }.to(beFalse())
                    expect { delegate.calledWillSendRequest }.to(beFalse())
                    expect { delegate.calledServerDidRespond }.to(beFalse())
                    expect { delegate.calledConnectionDidFail }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beTrue())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                    expect { try reporter.repository.countResources() }.to(equal(1))
                }
            }

            context("given new report") {
                throwingIt("can modify multiple reports via reporter attachments and attributes properties") {
                    let delegate = BacktraceClientDelegateMock()
                    let attachmentPaths = [URL(fileURLWithPath: "/path1"), URL(fileURLWithPath: "/path2")]
                    reporter.attachments += attachmentPaths
                    reporter.attributes = ["a": "b"]

                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    for _ in 0...5 {
                        let backtraceReport = try reporter.generate()
                        let result = reporter.send(resource: backtraceReport)

                        expect { result.backtraceStatus }.to(equal(.ok))
                        expect { result.report?.attachmentPaths }.to(equal(attachmentPaths.map(\.path)))
                        expect { result.report?.attributes["a"] as? String }.to(equal("b"))
                    }
                }

                throwingIt("can modify report and request if modified in willSend callbacks") {
                    let delegate = BacktraceClientDelegateMock()
                    let attachmentPaths = ["path1", "path2"]
                    let header = (key: "foo", value: "bar")
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        report.attachmentPaths += attachmentPaths
                        report.attributes = ["a": "b"]
                        return report
                    }

                    delegate.willSendRequestClosure = { request in
                        var request = request
                        request.addValue(header.key, forHTTPHeaderField: header.value)
                        return request
                    }

                    let result = reporter.send(resource: try reporter.generate())

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attachmentPaths }.to(equal(attachmentPaths))
                    expect { result.report?.attributes["a"] as? String }.to(equal("b"))

                    // Now result the closures and verify the attributes and attachments disappear
                    delegate.willSendClosure = { report in
                        return report
                    }
                    delegate.willSendRequestClosure = { request in
                        return request
                    }

                    let result2 = reporter.send(resource: try reporter.generate())

                    expect { result2.backtraceStatus }.to(equal(.ok))
                    expect { result2.report?.attachmentPaths }.to(beEmpty())
                    expect { result2.report?.attributes["a"] }.to(beNil())
                }

                it("report should have application version and session attributes") {
                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try reporter.generate()
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        expect { report.attributes["application.session"] }.notTo(beNil())
                        expect { report.attributes["application.version"] }.notTo(beNil())
                        return report
                    }

                    let result = reporter.send(resource: backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attributes["application.session"] }.notTo(beNil())
                    expect { result.report?.attributes["application.version"] }.notTo(beNil())
                }

                it("report should have metrics attributes") {
                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try reporter.generate()
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        expect { report.attributes["application.session"] }.toNot(beNil())
                        expect { report.attributes["application.version"] }.toNot(beNil())
                        return report
                    }

                    let result = reporter.send(resource: backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attributes["application.session"] }.toNot(beNil())
                    expect { result.report?.attributes["application.version"] }.toNot(beNil())
                }
#if os(iOS) && !targetEnvironment(macCatalyst)
                it("report should have breadcrumbs attributes if breadcrumbs is enabled") {
                    let breadcrumbs = BacktraceBreadcrumbs()
                    breadcrumbs.enableBreadcrumbs()

                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try reporter.generate()
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        expect { report.attributes["breadcrumbs.lastId"] }.toNot(beNil())
                        expect { report.attachmentPaths.first }.to(contain("bt-breadcrumbs-0"))
                        return report
                    }

                    let result = reporter.send(resource: backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attributes["breadcrumbs.lastId"] }.toNot(beNil())
                    expect { result.report?.attachmentPaths.first }.to(contain("bt-breadcrumbs-0"))

                    breadcrumbs.disableBreadcrumbs()
                }

                it("report should NOT have breadcrumbs attributes if breadcrumbs is NOT enabled") {
                    _ = BacktraceBreadcrumbs()

                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try reporter.generate()
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        expect { report.attributes["breadcrumbs.lastId"] }.to(beNil())
                        expect { report.attachmentPaths.first }.to(beNil())
                        return report
                    }

                    let result = reporter.send(resource: backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attributes["breadcrumbs.lastId"] }.to(beNil())
                    expect { result.report?.attachmentPaths.first }.to(beNil())
                }
#endif
            }

            context("given a pending native crash") {
                throwingIt("persists before purging and upserts a repeated payload") {
                    let generated = try BacktraceCrashReporter().generateLiveReport(attributes: [:])
                    let pending = try BacktraceReport(pendingReport: generated.reportData,
                                                      attributes: ["pending": true],
                                                      attachmentPaths: [])
                    let crashReporting = PendingCrashReportingMock(pendingReport: pending)
                    let pendingReporter = try BacktraceReporter(reporter: crashReporting,
                                                                api: backtraceApi,
                                                                dbSettings: BacktraceDatabaseSettings(),
                                                                credentials: credentials,
                                                                oomMode: .none,
                                                                urlSession: urlSession)
                    try pendingReporter.repository.clear()

                    try pendingReporter.handlePendingCrashes()
                    expect(try pendingReporter.repository.countResources()).to(equal(1))
                    expect(crashReporting.events).to(equal(["load", "purge"]))

                    try pendingReporter.handlePendingCrashes()
                    expect(try pendingReporter.repository.countResources()).to(equal(1))
                    expect(pendingReporter.watcher.repository === pendingReporter.repository).to(beTrue())
                    expect(pendingReporter.backtraceOomWatcher.repository === pendingReporter.repository).to(beTrue())
                }

                throwingIt("blocks replay until a failed source purge succeeds") {
                    let generated = try BacktraceCrashReporter().generateLiveReport(attributes: [:])
                    let pending = try BacktraceReport(pendingReport: generated.reportData,
                                                      attributes: [:],
                                                      attachmentPaths: [])
                    let crashReporting = PendingCrashReportingMock(pendingReport: pending)
                    crashReporting.purgeError = FileError.fileNotWritten
                    let pendingReporter = try BacktraceReporter(reporter: crashReporting,
                                                                api: backtraceApi,
                                                                dbSettings: BacktraceDatabaseSettings(),
                                                                credentials: credentials,
                                                                oomMode: .none,
                                                                urlSession: urlSession)
                    try pendingReporter.repository.clear()
                    urlSession.response = MockOkResponse()
                    urlSession.resetRequestCount()

                    expect { try pendingReporter.handlePendingCrashes() }.toNot(throwError())
                    expect(try pendingReporter.repository.countResources()).to(equal(1))
                    expect(try pendingReporter.repository.getLatest()).to(beEmpty())
                    expect(try pendingReporter.repository.persistedState(for: pending))
                        .to(equal(.awaitingSourcePurge))

                    let replay = BacktraceWatcher(settings: BacktraceDatabaseSettings(),
                                                  api: backtraceApi,
                                                  repository: pendingReporter.repository,
                                                  networkAvailabilityCheck: { true })
                    replay.batchRetry()
                    expect(urlSession.requestCount).to(equal(0))

                    crashReporting.purgeError = nil
                    try pendingReporter.handlePendingCrashes()
                    expect(try pendingReporter.repository.persistedState(for: pending))
                        .to(equal(.readyForInitialSubmission))
                    replay.batchInitialSubmission()
                    replay.batchInitialSubmission()

                    expect(urlSession.requestCount).to(equal(1))
                    expect(try pendingReporter.repository.countResources()).to(equal(0))
                }

                throwingIt("drops invalid optional attribute values without blocking ingestion") {
                    let generated = try BacktraceCrashReporter().generateLiveReport(attributes: [:])
                    let pending = try BacktraceReport(pendingReport: generated.reportData,
                                                      attributes: ["not-a-property-list": NSObject()],
                                                      attachmentPaths: [])
                    let crashReporting = PendingCrashReportingMock(pendingReport: pending)
                    let pendingReporter = try BacktraceReporter(reporter: crashReporting,
                                                                api: backtraceApi,
                                                                dbSettings: BacktraceDatabaseSettings(),
                                                                credentials: credentials,
                                                                oomMode: .none,
                                                                urlSession: urlSession)
                    try pendingReporter.repository.clear()

                    expect { try pendingReporter.handlePendingCrashes() }.toNot(throwError())
                    expect(crashReporting.events).to(equal(["load", "purge"]))
                    let persisted = try pendingReporter.repository.getInitialSubmission(count: 1).first
                    expect(persisted?.attributes["not-a-property-list"]).to(beNil())
                    expect(persisted?.attributes[BacktracePendingCrashMetadata.invalidAttributeValuesKey] as? Int)
                        .to(equal(1))
                }

                throwingIt("does not purge when repository-owned persistence is unavailable") {
                    let generated = try BacktraceCrashReporter().generateLiveReport(attributes: [:])
                    let pending = try BacktraceReport(pendingReport: generated.reportData,
                                                      attributes: [:],
                                                      attachmentPaths: [])
                    let crashReporting = PendingCrashReportingMock(pendingReport: pending)
                    let pendingReporter = try BacktraceReporter(reporter: crashReporting,
                                                                api: backtraceApi,
                                                                dbSettings: BacktraceDatabaseSettings(),
                                                                credentials: credentials,
                                                                oomMode: .none,
                                                                urlSession: urlSession)
                    try pendingReporter.repository.clear()
                    let attributesConfig = try AttributesStorage.AttributesConfig(
                        fileName: pending.identifier.uuidString,
                        directoryUrl: pendingReporter.repository.metadataDirectoryUrl
                    )
                    try FileManager.default.createDirectory(at: attributesConfig.fileUrl,
                                                            withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: attributesConfig.fileUrl) }

                    expect { try pendingReporter.handlePendingCrashes() }.to(throwError())

                    expect(crashReporting.events).to(equal(["load"]))
                    expect(crashReporting.hasPendingCrashes()).to(beTrue())
                    expect(try pendingReporter.repository.countResources()).to(equal(0))
                }

                throwingIt("persists and purges when an optional pending attachment is missing") {
                    let generated = try BacktraceCrashReporter().generateLiveReport(attributes: [:])
                    let missingAttachment = FileManager.default.temporaryDirectory
                        .appendingPathComponent("missing-\(UUID().uuidString).txt")
                    let pending = try BacktraceReport(pendingReport: generated.reportData,
                                                      attributes: [:],
                                                      attachmentPaths: [missingAttachment.path])
                    let crashReporting = PendingCrashReportingMock(pendingReport: pending)
                    let pendingReporter = try BacktraceReporter(reporter: crashReporting,
                                                                api: backtraceApi,
                                                                dbSettings: BacktraceDatabaseSettings(),
                                                                credentials: credentials,
                                                                oomMode: .none,
                                                                urlSession: urlSession)
                    try pendingReporter.repository.clear()

                    expect { try pendingReporter.handlePendingCrashes() }.toNot(throwError())
                    expect(crashReporting.events).to(equal(["load", "purge"]))
                    let persisted = try pendingReporter.repository.getInitialSubmission(count: 1).first
                    expect(persisted).toNot(beNil())
                    expect(persisted?.attachmentPaths).to(beEmpty())
                    expect(persisted?.attributes[BacktracePendingCrashMetadata.missingAttachmentsKey] as? Int)
                        .to(equal(1))
                }

                throwingIt("allows absent crash metadata sidecars and purges after persistence") {
                    let fileName = "absent-pending-sidecars-\(UUID().uuidString)"
                    try? AttributesStorage.remove(fileName: fileName)
                    try? AttachmentsStorage.remove(fileName: fileName)
                    let generated = try BacktraceCrashReporter().generateLiveReport(attributes: [:])
                    let pending = try BacktraceReport(pendingReport: generated.reportData,
                                                      attributes: [:],
                                                      attachmentPaths: [])
                    let crashReporting = PendingCrashReportingMock(
                        pendingReport: pending,
                        provider: {
                            let metadata = BacktracePendingCrashMetadata.load(fileName: fileName)
                            return try BacktraceReport(pendingReport: generated.reportData,
                                                       attributes: metadata.attributes,
                                                       attachmentPaths: metadata.attachmentPaths)
                        }
                    )
                    let pendingReporter = try BacktraceReporter(reporter: crashReporting,
                                                                api: backtraceApi,
                                                                dbSettings: BacktraceDatabaseSettings(),
                                                                credentials: credentials,
                                                                oomMode: .none,
                                                                urlSession: urlSession)
                    try pendingReporter.repository.clear()

                    try pendingReporter.handlePendingCrashes()

                    expect(crashReporting.events).to(equal(["load", "purge"]))
                    expect(crashReporting.hasPendingCrashes()).to(beFalse())
                    expect(try pendingReporter.repository.countResources()).to(equal(1))
                }

                throwingIt("preserves a corrupt attributes sidecar and continues ingesting the crash") {
                    let fileName = "corrupt-pending-attributes-\(UUID().uuidString)"
                    let config = try AttributesStorage.AttributesConfig(fileName: fileName)
                    try FileManager.default.createDirectory(at: config.directoryUrl,
                                                            withIntermediateDirectories: true)
                    try Data("not a property list".utf8).write(to: config.fileUrl, options: .atomic)
                    defer {
                        try? AttributesStorage.remove(fileName: fileName)
                        try? AttachmentsStorage.remove(fileName: fileName)
                    }

                    let generated = try BacktraceCrashReporter().generateLiveReport(attributes: [:])
                    let pending = try BacktraceReport(pendingReport: generated.reportData,
                                                      attributes: [:],
                                                      attachmentPaths: [])
                    let crashReporting = PendingCrashReportingMock(
                        pendingReport: pending,
                        provider: {
                            let metadata = BacktracePendingCrashMetadata.load(fileName: fileName)
                            let report = try BacktraceReport(pendingReport: generated.reportData,
                                                             attributes: metadata.attributes,
                                                             attachmentPaths: metadata.attachmentPaths)
                            report.pendingMetadataFilePaths = metadata.rawSidecarPaths
                            return report
                        }
                    )
                    let pendingReporter = try BacktraceReporter(reporter: crashReporting,
                                                                api: backtraceApi,
                                                                dbSettings: BacktraceDatabaseSettings(),
                                                                credentials: credentials,
                                                                oomMode: .none,
                                                                urlSession: urlSession)
                    try pendingReporter.repository.clear()

                    expect { try pendingReporter.handlePendingCrashes() }.toNot(throwError())

                    expect(crashReporting.events).to(equal(["load", "purge"]))
                    expect(crashReporting.hasPendingCrashes()).to(beFalse())
                    expect(FileManager.default.fileExists(atPath: config.fileUrl.path)).to(beTrue())
                    let persisted = try pendingReporter.repository.getInitialSubmission(count: 1).first
                    expect(persisted?.attributes[BacktracePendingCrashMetadata.attributesErrorKey] as? String)
                        .toNot(beNil())
                    let ownedSidecarDirectory = pendingReporter.repository.metadataDirectoryUrl
                        .appendingPathComponent("PendingMetadata", isDirectory: true)
                        .appendingPathComponent(pending.identifier.uuidString, isDirectory: true)
                    expect(try FileManager.default.contentsOfDirectory(atPath: ownedSidecarDirectory.path))
                        .toNot(beEmpty())
                }

                throwingIt("recovers valid bookmarks when another stored bookmark is invalid") {
                    let fileName = "corrupt-pending-attachments-\(UUID().uuidString)"
                    let config = try AttachmentsStorage.AttachmentsConfig(fileName: fileName)
                    try FileManager.default.createDirectory(at: config.directoryUrl,
                                                            withIntermediateDirectories: true)
                    defer {
                        try? AttributesStorage.remove(fileName: fileName)
                        try? AttachmentsStorage.remove(fileName: fileName)
                    }

                    let attachmentUrl = FileManager.default.temporaryDirectory
                        .appendingPathComponent("valid-pending-attachment-\(UUID().uuidString).txt")
                    try Data("attachment".utf8).write(to: attachmentUrl, options: .atomic)
                    defer { try? FileManager.default.removeItem(at: attachmentUrl) }
                    let validBookmark = try attachmentUrl.bookmarkData(options: .minimalBookmark)
                    let bookmarks: Bookmarks = [
                        attachmentUrl.path: validBookmark,
                        "invalid-bookmark": Data("not a bookmark".utf8)
                    ]
                    let sidecarData = try PropertyListSerialization.data(fromPropertyList: bookmarks,
                                                                         format: .binary,
                                                                         options: 0)
                    try sidecarData.write(to: config.fileUrl, options: .atomic)

                    let generated = try BacktraceCrashReporter().generateLiveReport(attributes: [:])
                    let pending = try BacktraceReport(pendingReport: generated.reportData,
                                                      attributes: [:],
                                                      attachmentPaths: [])
                    let crashReporting = PendingCrashReportingMock(
                        pendingReport: pending,
                        provider: {
                            let metadata = BacktracePendingCrashMetadata.load(fileName: fileName)
                            let report = try BacktraceReport(pendingReport: generated.reportData,
                                                             attributes: metadata.attributes,
                                                             attachmentPaths: metadata.attachmentPaths)
                            report.pendingMetadataFilePaths = metadata.rawSidecarPaths
                            return report
                        }
                    )
                    let pendingReporter = try BacktraceReporter(reporter: crashReporting,
                                                                api: backtraceApi,
                                                                dbSettings: BacktraceDatabaseSettings(),
                                                                credentials: credentials,
                                                                oomMode: .none,
                                                                urlSession: urlSession)
                    try pendingReporter.repository.clear()

                    expect { try pendingReporter.handlePendingCrashes() }.toNot(throwError())

                    expect(crashReporting.events).to(equal(["load", "purge"]))
                    expect(crashReporting.hasPendingCrashes()).to(beFalse())
                    expect(FileManager.default.fileExists(atPath: config.fileUrl.path)).to(beTrue())
                    let persisted = try pendingReporter.repository.getInitialSubmission(count: 1).first
                    expect(persisted?.attachmentPaths.count).to(equal(1))
                    expect(persisted?.attributes[BacktracePendingCrashMetadata.invalidBookmarksKey] as? Int)
                        .to(equal(1))
                }

                throwingIt("dead-letters a recurring invalid payload without blocking current capture") {
                    let generated = try BacktraceCrashReporter().generateLiveReport(attributes: [:])
                    let placeholder = try BacktraceReport(pendingReport: generated.reportData,
                                                          attributes: [:],
                                                          attachmentPaths: [])
                    let invalidData = Data("invalid-plcrash-payload-\(UUID().uuidString)".utf8)
                    let crashReporting = PendingCrashReportingMock(
                        pendingReport: placeholder,
                        provider: {
                            throw BacktracePendingCrashError.invalidPayload(data: invalidData,
                                                                            rawSidecarPaths: [],
                                                                            diagnostics: [:],
                                                                            underlying: FileError.invalidPropertyList)
                        }
                    )
                    let pendingReporter = try BacktraceReporter(reporter: crashReporting,
                                                                api: backtraceApi,
                                                                dbSettings: BacktraceDatabaseSettings(),
                                                                credentials: credentials,
                                                                oomMode: .none,
                                                                urlSession: urlSession)
                    try pendingReporter.repository.clear()

                    expect { try pendingReporter.handlePendingCrashes() }.toNot(throwError())
                    expect { try crashReporting.enableCrashReporting() }.toNot(throwError())

                    expect(crashReporting.hasPendingCrashes()).to(beFalse())
                    expect(crashReporting.events.filter { $0 == "load" }.count).to(equal(1))
                    expect(crashReporting.events.filter { $0 == "purge" }.count).to(equal(1))
                    expect(crashReporting.events.filter { $0 == "enable" }.count).to(equal(1))
                    expect(try pendingReporter.repository.countResources()).to(equal(0))
                }
            }
        }
    }
    // swiftlint:enable function_body_length force_try
}

private final class PendingCrashReportingMock: CrashReporting {
    let report: BacktraceReport
    var purgeError: Error?
    var events = [String]()
    private var pending = true
    private let provider: (() throws -> BacktraceReport)?

    init(pendingReport: BacktraceReport,
         provider: (() throws -> BacktraceReport)? = nil) {
        self.report = pendingReport
        self.provider = provider
    }

    func generateLiveReport(exception: NSException?,
                            attributes: Attributes,
                            attachmentPaths: [String]) throws -> BacktraceReport {
        return report
    }

    func pendingCrashReport() throws -> BacktraceReport {
        events.append("load")
        return try provider?() ?? report
    }

    func purgePendingCrashReport() throws {
        events.append("purge")
        if let purgeError = purgeError { throw purgeError }
        pending = false
    }

    func hasPendingCrashes() -> Bool { return pending }
    func enableCrashReporting() throws { events.append("enable") }
    func signalContext(_ mutableContext: inout SignalContext) {}
    func setCustomData(data: Data) {}
}
