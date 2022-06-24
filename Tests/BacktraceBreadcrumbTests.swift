import XCTest
import Nimble
import Quick

@testable import Backtrace

final class BacktraceBreadcrumbTests: QuickSpec {
    
    override func spec() {
        describe("Breadcrumbs") {
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            let dbSettings = BacktraceDatabaseSettings()
            let reportsPerMin = 3
            var configuration: BacktraceClientConfiguration?

            beforeEach {
                configuration = BacktraceClientConfiguration(credentials: credentials, dbSettings: dbSettings,
                                                                 reportsPerMin: reportsPerMin)
            }
            afterEach {
                configuration = nil
            }
            context("breadcrumb is not enabled") {
                it("fails to add breadcrumb") {
                    let result = configuration?.addBreadcrumb("Breadcrumb submit test")
                    expect { result }.to(beFalse())
                }
            }
            context("breadcrumb is enabled") {
                it("Able to add breadcrumb") {
                    configuration?.enableBreadCrumbs()
                    let result = configuration?.addBreadcrumb("Breadcrumb submit test")
                    expect { result }.to(beTrue())
                }
            }
        }
    }
}
