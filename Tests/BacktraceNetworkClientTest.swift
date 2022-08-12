import XCTest
import Nimble
import Quick
@testable import Backtrace

class BacktraceNetworkClientTest: QuickSpec {

    override func spec() {
        describe("BacktraceNetworkClient") {
            context("when used concurrently, it doesn't crash") {
                let client = BacktraceNetworkClient(urlSession: URLSession.shared)
                let group = DispatchGroup()
                if let url = URL(string: "http://localhost") {
                    let urlRequest = URLRequest(url: url)
                    for _ in 1...10 {
                        DispatchQueue.global().async(group: group) {
                            _ = try? client.send(request: urlRequest)
                        }
                    }
                    group.wait()
                }
            }
        }
    }
}
