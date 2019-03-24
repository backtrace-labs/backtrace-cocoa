import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceWatcherTests: QuickSpec {
    //swiftlint:disable function_body_length
    override func spec() {
        describe("Watcher") {
            let dbSettings = BacktraceDatabaseSettings()
            let networkClientMockConfig = BacktraceApiMock.Configuration.validCredentials
            let api = BacktraceApiMock(config: networkClientMockConfig)
            let repository = WatcherRepositoryMock()
            
            context("when passed correct parameters") {
                it("then initialize without throwing error") {
                    expect {
                        try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3, api: api,
                                             repository: repository, batchSize: 3)
                    }.notTo(throwError())
                }
                
                throwingIt("then pass prameters properly") {
                    let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3, api: api,
                                                       repository: repository, batchSize: 3)
                    expect(watcher.settings).to(be(dbSettings))
                    expect(watcher.reportsPerMin).to(equal(3))
                    expect(watcher.api).to(be(api))
                    expect(watcher.repository).to(be(repository))
                    expect(watcher.batchSize).to(equal(3))
                    expect(watcher.timer).toNot(beNil())
                }
                
                context("with RetryBehaviour.none") {
                    throwingIt("then timer should be nil") {
                        dbSettings.retryBehaviour = .none
                        let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3, api: api,
                                                           repository: repository, batchSize: 3)
                        expect(watcher.timer).to(beNil())
                    }
                }
            }
            
            context("when configure timer with handler") {
                throwingIt("then timer fires handler") {
                    dbSettings.retryInterval = 1
                    let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3, api: api,
                                                       repository: repository, batchSize: 3)
                    watcher.resetTimer()
                    
                    waitUntil(timeout: TimeInterval(dbSettings.retryInterval + 1)) { done in
                        watcher.configureTimer(with: DispatchWorkItem(block: {
                            done()
                        }))
                    }
                }
            }
            
            describe("retrive crashes from repository") {
                throwingBeforeEach {
                    try repository.clear()
                }
                
                context("when retrive") {
                    throwingIt("then not throw error") {
                        let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3, api: api,
                                                           repository: repository, batchSize: 3)
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

                        expect { try watcher.crashReportsFromRepository(limit: 1) }.toNot(throwError())
                    }
                }
                
                context("when retrive in queue order") {
                    throwingIt("then get oldest") {
                        dbSettings.retryOrder = .queue
                        let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3, api: api,
                                                           repository: repository, batchSize: 3)
                        let firstReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
                        try repository.save(firstReport)
                        let secondReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 2])
                        try repository.save(secondReport)
                        let thirdReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 3])
                        try repository.save(thirdReport)

                        let reports = try watcher.crashReportsFromRepository(limit: 2)
                        expect(reports.count).to(equal(2))
                        expect(reports).toNot(contain(firstReport))
                        expect(reports).to(contain(secondReport, thirdReport))
                    }
                }
                
                context("when retrive in stack order ") {
                    throwingIt("then get latest") {
                        dbSettings.retryOrder = .stack
                        let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3, api: api,
                                                           repository: repository, batchSize: 3)
                        let firstReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
                        try repository.save(firstReport)
                        let secondReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 2])
                        try repository.save(secondReport)
                        let thirdReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 3])
                        try repository.save(thirdReport)

                        let reports = try watcher.crashReportsFromRepository(limit: 2)
                        
                        expect(reports.count).to(equal(2))
                        expect(reports).toNot(contain(thirdReport))
                        expect(reports).to(contain(firstReport, secondReport))
                    }
                }
            }
            
            describe("batch retry") {
                throwingBeforeEach {
                    try repository.clear()
                }
                
                context("when send one-element batch successfully") {
                    throwingIt("then watcher not throwing error") {
                        let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3, api: api,
                                                           repository: repository, batchSize: 3)
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))
                        
                        expect { try watcher.batchRetry() }.toNot(throwError())
                    }
                    
                    throwingIt("then report is removed from repository") {
                        let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3, api: api,
                                                           repository: repository, batchSize: 3)
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))
                        try watcher.batchRetry()
                        
                        expect(try watcher.repository.countResources()).to(equal(0))
                    }
                }
                
                context("when send two-element batch successfully") {
                    throwingIt("then all sent reports are removed from repository") {
                        let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3, api: api,
                                                           repository: repository, batchSize: 3)
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 2]))
                        try watcher.batchRetry()
                        
                        expect(try watcher.repository.countResources()).to(equal(0))
                    }
                }
                
                context("when connection error") {
                    throwingIt("then do nothing") {
                        let networkClientMockConfig = BacktraceApiMock.Configuration.invalidEndpoint
                        let failureNetworkClient = BacktraceApiMock(config: networkClientMockConfig)
                        let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3,
                                                           api: failureNetworkClient, repository: repository,
                                                           batchSize: 3)
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))
                        
                        try watcher.batchRetry()
                        expect(try watcher.repository.countResources()).to(equal(1))
                    }
                }
                
                context("when limit reached error") {
                    let networkClientMockConfig = BacktraceApiMock.Configuration.limitReached
                    let failureNetworkClient = BacktraceApiMock(config: networkClientMockConfig)
                    throwingIt("then report is not removed from repository") {
                        let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3,
                                                           api: failureNetworkClient, repository: repository,
                                                           batchSize: 3)
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))
                        
                        try watcher.batchRetry()
                        expect(try watcher.repository.countResources()).to(equal(1))
                    }
                    
                    throwingIt("then increment counter") {
                        let watcher = try BacktraceWatcher(settings: dbSettings, reportsPerMin: 3,
                                                           api: failureNetworkClient, repository: repository,
                                                           batchSize: 3)
                        let report = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
                        try repository.save(report)
                        
                        expect(watcher.repository.retryCount(for: report)).to(equal(0))
                        try watcher.batchRetry()
                        expect(watcher.repository.retryCount(for: report)).to(equal(1))
                    }
                }
            }
        }
        //swiftlint:enable function_body_length
    }
    
    private static func backtraceReport(for attributes: Attributes) throws -> BacktraceReport {
        let crashReporter = CrashReporter()
        return try crashReporter.generateLiveReport(attributes: attributes)
    }
}
