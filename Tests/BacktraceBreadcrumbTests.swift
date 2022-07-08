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
    
    func raadBreadcrumb() -> [[String:Any]]? {
        do {
            let path = try breadcrumbLogPath(true)
            let fileURL = URL(fileURLWithPath: path)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            return convertStringIntoBreadcrumb(content)
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen try to read breadcrumbs log file")
            return nil
        }
    }
    
    func convertStringIntoBreadcrumb(_ text: String) -> [[String:Any]]? {
        if let data = text.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
            } catch {
                BacktraceLogger.warning("\(error.localizedDescription) \nWhen try to convert text into json object")
                return nil
            }
        }
        return nil
    }
    
    override func spec() {
        describe("Breadcrumbs") {
            var breadCrumb: BacktraceBreadcrumb?
            beforeEach {
                do {
                    try FileManager.default.removeItem(atPath: try self.breadcrumbLogPath(false))
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
                    let breadcrumbs = self.raadBreadcrumb()
                    expect { breadcrumbs?.count ?? 0 }.to(equal(0))
                }
            }
            context("breadcrumb is enabled") {
                it("Able to add breadcrumb") {
                    breadCrumb?.enableBreadCrumbs()
                    expect { breadCrumb?.isBreadcrumbsEnabled }.to(beTrue())
                    expect { breadCrumb?.getCurrentBreadcrumbId }.toNot(beNil())
                    let result = breadCrumb?.addBreadcrumb("Breadcrumb submit test")
                    expect { result }.to(beTrue())
                    let breadcrumbs = self.raadBreadcrumb()
                    expect { breadcrumbs?.count ?? 0 }.to(equal(1))
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
