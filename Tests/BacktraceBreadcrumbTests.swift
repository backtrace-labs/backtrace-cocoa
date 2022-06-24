import XCTest
import Nimble
import Quick

@testable import Backtrace

final class BacktraceBreadcrumbTests: QuickSpec {
    
    override func spec() {
        describe("Breadcrumbs") {
            let breadcrumb = BacktraceBreadcrumb()
            
            context("breadcrumb is not enabled") {
                it("fails to add breadcrumb") {
                    let dbSettings = BacktraceDatabaseSettings()
                    let reportsPerMin = 3
                    let configuration = BacktraceClientConfiguration(credentials: credentials, dbSettings: dbSettings,
                                                                     reportsPerMin: reportsPerMin)
                    
                    let result = configuration.addBreadcrumb("Breadcrumb submit test")

                    let result = reporter.send(resource: backtraceReport)
                    expect { result }.to(beFalse()())
                }
            }
            
            context("breadcrumb is enabled") {
                it("Able to add breadcrumb") {
                    let dbSettings = BacktraceDatabaseSettings()
                    let reportsPerMin = 3
                    let configuration = BacktraceClientConfiguration(credentials: credentials, dbSettings: dbSettings,
                                                                     reportsPerMin: reportsPerMin)
                    configuration.enableBreadCrumbs()
                    
                    let result = configuration.addBreadcrumb("Breadcrumb submit test")

                    let result = reporter.send(resource: backtraceReport)
                    expect { result }.to(beTrue()())
                }
            }
        }
    }
}
