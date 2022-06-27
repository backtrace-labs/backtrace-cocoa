import XCTest
import Nimble
import Quick

@testable import Backtrace

final class BacktraceBreadcrumbTests: QuickSpec {
    
    override func spec() {
        describe("Breadcrumbs") {
            
            var breadCrumb: BacktraceBreadcrumb?

            beforeEach {
                breadCrumb = BacktraceBreadcrumb()
            }
            afterEach {
                breadCrumb = nil
            }
            context("breadcrumb is not enabled") {
                it("fails to add breadcrumb") {
                    expect { breadCrumb?.isBreadcrumbsEnabled }.to(beFalse())
                    expect { breadCrumb?.getCurrentBreadcrumbId }.to(beNil())
                    let result = breadCrumb?.addBreadcrumb("Breadcrumb submit test")
                    expect { result }.to(beFalse())
                }
            }
            context("breadcrumb is enabled") {
                it("Able to add breadcrumb") {
                    breadCrumb?.enableBreadCrumbs()
                    expect { breadCrumb?.isBreadcrumbsEnabled }.to(beTrue())
                    expect { breadCrumb?.getCurrentBreadcrumbId }.toNot(beNil())
                    let result = breadCrumb?.addBreadcrumb("Breadcrumb submit test")
                    expect { result }.to(beTrue())
                }
                it("Again disable breadcrumb") {
                    breadCrumb?.disableBreadCrumbs()
                    expect { breadCrumb?.isBreadcrumbsEnabled }.to(beFalse())
                    expect { breadCrumb?.getCurrentBreadcrumbId }.to(beNil())
                }
            }
        }
    }
}
