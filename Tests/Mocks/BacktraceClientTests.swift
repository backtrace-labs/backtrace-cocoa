import XCTest

import Nimble
import Quick
#if SWIFT_PACKAGE
import CrashReporter
#else
import Backtrace_PLCrashReporter
#endif
@testable import Backtrace

final class BacktraceClientTests: QuickSpec {

    // swiftlint:disable function_body_length
    override func spec() {

        describe("Backtrace client") {
            throwingContext("given default values") {
                guard let endpoint = URL(string: "https://wwww.backtrace.io") else { fail(); return }
                let token = "token"
                let credentials = BacktraceCredentials(endpoint: endpoint, token: token)

                it("has default database settings") {
                    let defaultDbSettings = BacktraceDatabaseSettings()
                    expect(defaultDbSettings.maxDatabaseSize).to(equal(0))
                    expect(defaultDbSettings.maxRecordCount).to(equal(0))
                    expect(defaultDbSettings.retryInterval).to(equal(5))
                    expect(defaultDbSettings.retryLimit).to(equal(3))
                    expect(defaultDbSettings.retryBehaviour.rawValue).to(equal(RetryBehaviour.interval.rawValue))
                    expect(defaultDbSettings.retryOrder.rawValue).to(equal(RetryOrder.queue.rawValue))
                    expect(defaultDbSettings.maxDatabaseSizeInBytes).to(equal(0))
                }

                it("has default configuration") {
                    let dbSettings = BacktraceDatabaseSettings()
                    let reportsPerMin = 3
                    let configuration = BacktraceClientConfiguration(credentials: credentials, dbSettings: dbSettings,
                                                                     reportsPerMin: reportsPerMin)
                    expect(configuration.credentials).to(be(credentials))
                    expect(configuration.reportsPerMin).to(equal(reportsPerMin))
                    expect(configuration.dbSettings).to(be(dbSettings))
                }

                it("can create instance of BacktraceClient") {
                    expect { try BacktraceClient(credentials: credentials) }.notTo(throwError())
                }

                it("modifies the default values") {
                    let customDbSettings = BacktraceDatabaseSettings()
                    let maxRecordCount = 10
                    let maxDatabaseSize = 10
                    let retryInterval = 10
                    let retryBehaviour = RetryBehaviour.interval
                    let retryOrder = RetryOrder.stack
                    let retryLimit = 10

                    customDbSettings.maxRecordCount = maxRecordCount
                    customDbSettings.maxDatabaseSize = maxDatabaseSize
                    customDbSettings.retryInterval = retryInterval
                    customDbSettings.retryBehaviour = retryBehaviour
                    customDbSettings.retryOrder = retryOrder
                    customDbSettings.retryLimit = retryLimit

                    expect(customDbSettings.maxDatabaseSize).to(equal(maxDatabaseSize))
                    expect(customDbSettings.maxRecordCount).to(equal(maxRecordCount))
                    expect(customDbSettings.retryInterval).to(equal(retryInterval))
                    expect(customDbSettings.retryLimit).to(equal(retryLimit))
                    expect(customDbSettings.retryBehaviour.rawValue).to(equal(retryBehaviour.rawValue))
                    expect(customDbSettings.retryOrder.rawValue).to(equal(retryOrder.rawValue))
                    expect(customDbSettings.maxDatabaseSizeInBytes).to(equal(1024 * 1024 * maxDatabaseSize))
                }
            }
        }
    }
    // swiftlint:enable function_body_length
}
