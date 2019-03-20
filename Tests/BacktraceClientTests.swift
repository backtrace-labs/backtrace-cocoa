import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceClientTests: QuickSpec {
    
    override func spec() {
        describe("Backtrace client") {
            it("has all fields equal to specified", closure: {
                let endpoint = URL(string: "https://wwww.backtrace.io")!
                let token = "token"
                let credentials = BacktraceCredentials(endpoint: endpoint, token: token)
                expect(credentials.endpoint).to(be(endpoint))
                expect(credentials.token).to(be(token))
            })
            describe("Database settings", {
                it("has default values", closure: {
                    let defaultDbSettings = BacktraceDatabaseSettings()
                    expect(defaultDbSettings.maxDatabaseSize).to(be(0))
                    expect(defaultDbSettings.maxRecordCount).to(be(0))
                    expect(defaultDbSettings.retryInterval).to(be(5))
                    expect(defaultDbSettings.retryLimit).to(be(3))
                    expect(defaultDbSettings.retryBehaviour.rawValue).to(be(RetryBehaviour.interval.rawValue))
                    expect(defaultDbSettings.retryOrder.rawValue).to(be(RetryOder.queue.rawValue))
                    expect(defaultDbSettings.maxDatabaseSizeInBytes).to(be(0))
                })
                
                it("modifies the default values", closure: {
                    let customDbSettings = BacktraceDatabaseSettings()
                    let maxRecordCount = 10
                    let maxDatabaseSize = 10
                    let retryInterval = 10
                    let retryBehaviour = RetryBehaviour.interval
                    let retryOrder = RetryOder.stack
                    let retryLimit = 10
                    
                    customDbSettings.maxRecordCount = maxRecordCount
                    customDbSettings.maxDatabaseSize = maxDatabaseSize
                    customDbSettings.retryInterval = retryInterval
                    customDbSettings.retryBehaviour = retryBehaviour
                    customDbSettings.retryOrder = retryOrder
                    customDbSettings.retryLimit = retryLimit
                    
                    expect(customDbSettings.maxDatabaseSize).to(be(maxDatabaseSize))
                    expect(customDbSettings.maxRecordCount).to(be(maxRecordCount))
                    expect(customDbSettings.retryInterval).to(be(retryInterval))
                    expect(customDbSettings.retryLimit).to(be(retryLimit))
                    expect(customDbSettings.retryBehaviour.rawValue).to(be(retryBehaviour.rawValue))
                    expect(customDbSettings.retryOrder.rawValue).to(be(retryOrder.rawValue))
                    expect(customDbSettings.maxDatabaseSizeInBytes).to(be(1024 * 1024 * maxDatabaseSize))
                })
            })
            describe("Client configuration", {
                it("has default values", closure: {
                    let endpoint = URL(string: "https://wwww.backtrace.io")!
                    let token = "token"
                    let credentials = BacktraceCredentials(endpoint: endpoint, token: token)
                    let dbSettings = BacktraceDatabaseSettings()
                    let reportsPerMin = 3
                    let configuration = BacktraceClientConfiguration(credentials: credentials, dbSettings: dbSettings, reportsPerMin: reportsPerMin)
                    expect(configuration.credentials).to(be(credentials))
                    expect(configuration.reportsPerMin).to(be(reportsPerMin))
                    expect(configuration.dbSettings).to(be(dbSettings))
                })
            })
            
            describe("Client", {
                context("has valid configuration", closure: {
                    let endpoint = URL(string: "https://wwww.backtrace.io")!
                    let token = "token"
                    let credentials = BacktraceCredentials(endpoint: endpoint, token: token)
                    expect { try BacktraceClient(credentials: credentials) }.notTo(throwError())
                })
            })
        }
    }
}
