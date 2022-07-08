import XCTest
import Nimble
import Quick

@testable import Backtrace

final class BacktraceBreadcrumbTests: QuickSpec {
    
    let breadcrumbLogFileName = "bt-breadcrumbs-0"
    let defaultMaxLogSize = 64000
    func breadcrumbLogPath(_ create: Bool) throws -> String {
        var fileURL = try FileManager.default.url(for: .documentDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: create)
        fileURL.appendPathComponent(breadcrumbLogFileName)
        return fileURL.path
    }
    
    func readBreadcrumbText() -> String? {
        do {
            let path = try breadcrumbLogPath(true)
            let fileURL = URL(fileURLWithPath: path)
            let content = try String(contentsOf: fileURL, encoding: .ascii)
            return content
        } catch {
            return nil
        }
    }
    
    override func spec() {
        describe("Breadcrumbs") {
            
            var breadCrumb: BacktraceBreadcrumb?

            beforeEach {
                do {
                    try FileManager.default.removeItem(atPath: self.breadcrumbLogPath(false))
                } catch {
                }
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
                    let breadcrumbText = self.readBreadcrumbText()
                    expect { breadcrumbText?.contains("Breadcrumb submit test") }.to(beFalse())
                }
            }
            context("breadcrumb is enabled") {
                it("Able to add breadcrumb") {
                    breadCrumb?.enableBreadCrumbs()
                    expect { breadCrumb?.isBreadcrumbsEnabled }.to(beTrue())
                    expect { breadCrumb?.getCurrentBreadcrumbId }.toNot(beNil())
                    let result = breadCrumb?.addBreadcrumb("Breadcrumb submit test")
                    expect { result }.to(beTrue())
                    let breadcrumbText = self.readBreadcrumbText()
                    expect { breadcrumbText?.contains("Breadcrumb submit test") }.to(beTrue())
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
