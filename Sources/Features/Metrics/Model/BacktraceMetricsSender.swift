import Foundation

final class BacktraceMetricsSender {

    private let api: BacktraceApi
    private let metricsContainer: BacktraceMetricsContainer
    private let settings: BacktraceMetricsSettings

    private let baseUrlString: String

    enum MetricsUrlPrefix: CustomStringConvertible {
      case summed
      case unique

      var description: String {
        switch self {
        case .summed: return "summed-events"
        case .unique: return "unique-events"
        }
      }
    }

    init(api: BacktraceApi, metricsContainer: BacktraceMetricsContainer, settings: BacktraceMetricsSettings) {
        self.api = api
        self.metricsContainer = metricsContainer
        self.settings = settings
        self.baseUrlString = defaultMetricsBaseUrlString
    }

    func enable() {
        // No need to do in the running thread, can be backgrounded
        DispatchQueue.global(qos: .background).async {
            self.sendStartupEvents()
        }
    }

    private func sendStartupEvents() {
        sendStartupSummedEvent()
        sendStartupUniqueEvent()
    }

    private func sendStartupUniqueEvent() {
        sendUniqueEvent()
    }

    private func sendStartupSummedEvent() {
        sendSummedEvent()
    }

    private func sendUniqueEvent() {
        let payload = metricsContainer.getUniqueEventsPayload()

        do {
            let url = try getSubmissionUrl(urlPrefix: MetricsUrlPrefix.unique)
            api.sendMetrics(payload, url: url)
        } catch {
            BacktraceLogger.error(error)
        }
    }

    private func sendSummedEvent() {
        // TODO: Unit test me
        defer { metricsContainer.clearSummedEvents() }

        let payload = metricsContainer.getSummedEventsPayload()

        do {
            let url = try getSubmissionUrl(urlPrefix: MetricsUrlPrefix.summed)
            api.sendMetrics(payload, url: url)
        } catch {
            BacktraceLogger.error(error)
        }
    }

    func getSubmissionUrl(urlPrefix: MetricsUrlPrefix) throws -> URL {
        let token = try api.credentials.getSubmissionToken()
        let universe = try api.credentials.getUniverseName()

        guard let baseUrl = URL(string: baseUrlString) else {
            throw BacktraceUrlParsingError.invalidInput(baseUrlString)
        }

        guard var components = URLComponents(url: baseUrl, resolvingAgainstBaseURL: true) else {
            throw BacktraceUrlParsingError.invalidInput(baseUrl.debugDescription)
        }

        components.path += urlPrefix.description + "/submit"
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "universe", value: universe)
        ]

        guard let url = components.url else {
            throw BacktraceUrlParsingError.invalidInput(baseUrl.debugDescription)
        }

        return url
    }
}
