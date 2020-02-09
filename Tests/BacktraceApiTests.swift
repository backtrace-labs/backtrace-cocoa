import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceApiTests: QuickSpec {
    //swiftlint:disable function_body_length
    override func spec() {
        describe("Api") {
            context("has valid endpoint and token", closure: {
                let endpoint = URL(string: "https://www.backtrace.io")!
                let token = "token"
                let backtraceCredentials = BacktraceCredentials(endpoint: endpoint, token: token)
                let urlSession = URLSessionMock()
                let api = BacktraceApi(credentials: backtraceCredentials, session: urlSession, reportsPerMin: 30)
                
                it("has no delegate attached", closure: {
                    expect(api.delegate).to(beNil())
                })
                
                it("has delegate attached", closure: {
                    let delegate = BacktraceClientDelegateMock()
                    api.delegate = delegate
                    expect(api.delegate).toNot(beNil())
                })
                
                it("has empty timestamps list", closure: {
                    expect(api.backtraceRateLimiter.timestamps).to(beEmpty())
                })
                
                context("has well formed backtrace report", closure: {
                    let crashReporter = CrashReporter()
                    
                    it("returns 200 response", closure: {
                        expect { () -> BacktraceReportStatus in
                            let backtraceReport = try crashReporter.generateLiveReport(attributes: [:])
                            urlSession.response = MockOkResponse(url: endpoint)
                            return try api.send(backtraceReport).backtraceStatus
                        }.to(equal(BacktraceReportStatus.ok))
                    })
                    
                    it("can modify the report before sending", closure: {
                        let delegate = BacktraceClientDelegateMock()
                        let attachmentPaths = ["path1", "path2"]
                        delegate.willSendClosure = {
                            $0.attachmentPaths = attachmentPaths
                            return $0
                        }
                        api.delegate = delegate
                        expect { () -> [String] in
                            let backtraceReport = try crashReporter.generateLiveReport(attributes: [:])
                            urlSession.response = MockOkResponse(url: endpoint)
                            return try api.send(backtraceReport).report?.attachmentPaths ?? []
                            }.to(equal(attachmentPaths))
                    })
                })
                
                context("has invalid token", {
                    let crashReporter = CrashReporter()
                    
                    it("returns 403 response", closure: {
                        expect { () -> BacktraceReportStatus in
                            let backtraceReport = try crashReporter.generateLiveReport(attributes: [:])
                            urlSession.response = Mock403Response(url: endpoint)
                            return try api.send(backtraceReport).backtraceStatus
                        }.to(equal(BacktraceReportStatus.serverError))
                    })
                })
                
                context("has no Internet connection", {
                    let crashReporter = CrashReporter()
                    
                    it("returns error", closure: {
                        expect { () -> BacktraceReportStatus in
                            let backtraceReport = try crashReporter.generateLiveReport(attributes: [:])
                            urlSession.response = MockConnectionErrorResponse(url: endpoint)
                            return try api.send(backtraceReport).backtraceStatus
                        }.to(throwError())
                    })
                    
                    it("returns no response", closure: {
                        expect { () -> BacktraceReportStatus in
                            let backtraceReport = try crashReporter.generateLiveReport(attributes: [:])
                            urlSession.response = MockNoResponse()
                            return try api.send(backtraceReport).backtraceStatus
                        }.to(throwError(HttpError.unknownError))
                    })
                })
            })
        }
    }
    //swiftlint:enable function_body_length
}
