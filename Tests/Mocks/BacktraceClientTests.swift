import Testing
import Foundation
@testable import Backtrace

@Suite struct BacktraceClientTests {

    private let endpoint = URL(string: "https://wwww.backtrace.io")!
    private let token = "token"

    private var credentials: BacktraceCredentials {
        BacktraceCredentials(endpoint: endpoint, token: token)
    }

    @Test("Has default database settings")
    func defaultDatabaseSettings() {
        let defaultDbSettings = BacktraceDatabaseSettings()
        #expect(defaultDbSettings.maxDatabaseSize == 0)
        #expect(defaultDbSettings.maxRecordCount == 0)
        #expect(defaultDbSettings.retryInterval == 5)
        #expect(defaultDbSettings.retryLimit == 3)
        #expect(defaultDbSettings.retryBehaviour.rawValue == RetryBehaviour.interval.rawValue)
        #expect(defaultDbSettings.retryOrder.rawValue == RetryOrder.queue.rawValue)
        #expect(defaultDbSettings.maxDatabaseSizeInBytes == 0)
    }

    @Test("Has default configuration")
    func defaultConfiguration() {
        let dbSettings = BacktraceDatabaseSettings()
        let reportsPerMin = 3
        let configuration = BacktraceClientConfiguration(credentials: credentials, dbSettings: dbSettings,
                                                         reportsPerMin: reportsPerMin)
        #expect(configuration.credentials === credentials)
        #expect(configuration.reportsPerMin == reportsPerMin)
        #expect(configuration.dbSettings === dbSettings)
    }

    @Test("Can create instance of BacktraceClient")
    func canCreateBacktraceClientInstance() throws {
        #expect(throws: Never.self) {
            try BacktraceClient(credentials: BacktraceCredentials(endpoint: URL(string: "https://wwww.backtrace.io")!,
                                                                  token: "token"))
        }
    }

    @Test("Modifies the default values")
    func modifiesDefaultValues() {
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

        #expect(customDbSettings.maxDatabaseSize == maxDatabaseSize)
        #expect(customDbSettings.maxRecordCount == maxRecordCount)
        #expect(customDbSettings.retryInterval == retryInterval)
        #expect(customDbSettings.retryLimit == retryLimit)
        #expect(customDbSettings.retryBehaviour.rawValue == retryBehaviour.rawValue)
        #expect(customDbSettings.retryOrder.rawValue == retryOrder.rawValue)
        #expect(customDbSettings.maxDatabaseSizeInBytes == 1024 * 1024 * maxDatabaseSize)
    }
}
