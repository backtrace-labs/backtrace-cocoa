import Testing
@testable import Backtrace
import Foundation

@Suite("Backtrace Credentials")
struct BacktraceCredentialsTests {

    let fakeUniverse = "universe"
    let fakeToken = "aaaaabbbbbccccf82668682e69f59b38e0a853bed941e08e85f4bf5eb2c5458"

    var legacyUrl: String {
        "https://" + fakeUniverse + ".sp.backtrace.io:6098/post?format=json&token=" + fakeToken
    }

    var url: String {
        "https://submit.backtrace.io/" + fakeUniverse + "/" + fakeToken + "/json"
    }

    var legacyUrlEndpoint: String {
        "https://" + fakeUniverse + ".sp.backtrace.io:6098"
    }

    // MARK: - Given legacy URL endpoint and token

    @Test("Can get universe name from legacy URL endpoint and token")
    func universeNameFromLegacyEndpointAndToken() throws {
        let credentials = BacktraceCredentials(endpoint: URL(string: legacyUrlEndpoint)!, token: fakeToken)
        #expect(try credentials.getUniverseName() == fakeUniverse)
    }

    @Test("Can get token from legacy URL endpoint and token")
    func tokenFromLegacyEndpointAndToken() throws {
        let credentials = BacktraceCredentials(endpoint: URL(string: legacyUrlEndpoint)!, token: fakeToken)
        #expect(try credentials.getSubmissionToken() == fakeToken)
    }

    // MARK: - Given legacy URI

    @Test("Can get universe name from legacy URI")
    func universeNameFromLegacyUri() throws {
        let credentials = BacktraceCredentials(submissionUrl: URL(string: legacyUrl)!)
        #expect(try credentials.getUniverseName() == fakeUniverse)
    }

    @Test("Can get token from legacy URI")
    func tokenFromLegacyUri() throws {
        let credentials = BacktraceCredentials(submissionUrl: URL(string: legacyUrl)!)
        #expect(try credentials.getSubmissionToken() == fakeToken)
    }

    // MARK: - Given URI

    @Test("Can get universe name from URI")
    func universeNameFromUri() throws {
        let credentials = BacktraceCredentials(submissionUrl: URL(string: url)!)
        #expect(try credentials.getUniverseName() == fakeUniverse)
    }

    @Test("Can get token from URI")
    func tokenFromUri() throws {
        let credentials = BacktraceCredentials(submissionUrl: URL(string: url)!)
        #expect(try credentials.getSubmissionToken() == fakeToken)
    }
}
