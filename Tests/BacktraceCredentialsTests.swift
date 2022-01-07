import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceCredentialsTests: QuickSpec {

    override func spec() {
        let fakeUniverse = "universe"
        let fakeToken = "aaaaabbbbbccccf82668682e69f59b38e0a853bed941e08e85f4bf5eb2c5458"
        let legacyUrl = "https://" + fakeUniverse + ".sp.backtrace.io:6098/post?format=json&token=" + fakeToken
        let url = "https://submit.backtrace.io/" + fakeUniverse + "/" + fakeToken + "/json"
        let legacyUrlEndpoint = "https://" + fakeUniverse + ".sp.backtrace.io:6098"

        describe("Backtrace Credentials") {
            context("Given legacy URL endpoint and token") {
                let credentials = BacktraceCredentials(endpoint: URL(string: legacyUrlEndpoint)!, token: fakeToken)
                it("Can get Universe name") {
                    expect { try credentials.getUniverseName() }.to(equal(fakeUniverse))
                }
                it("Can get token") {
                    expect { try credentials.getSubmissionToken() }.to(equal(fakeToken))
                }
            }

            context("Given legacy URI") {
                let credentials = BacktraceCredentials(submissionUrl: URL(string: legacyUrl)!)
                it("Can get Universe name") {
                    expect { try credentials.getUniverseName() }.to(equal(fakeUniverse))
                }
                it("Can get token") {
                    expect { try credentials.getSubmissionToken() }.to(equal(fakeToken))
                }
            }

            context("Given URI") {
                let credentials = BacktraceCredentials(submissionUrl: URL(string: url)!)
                it("Can get Universe name") {
                    expect { try credentials.getUniverseName() }.to(equal(fakeUniverse))
                }
                it("Can get token") {
                    expect { try credentials.getSubmissionToken() }.to(equal(fakeToken))
                }
            }
        }
    }
}
