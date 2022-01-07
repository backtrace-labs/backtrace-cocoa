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
        sendStartupEvents()
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
            let result = try api.sendMetrics(payload, url: url)
            handleUniqueEventsResult(result: result)
        } catch {
            BacktraceLogger.error(error)
        }
    }

    private func sendSummedEvent() {
        let payload = metricsContainer.getSummedEventsPayload()

        do {
            let url = try getSubmissionUrl(urlPrefix: MetricsUrlPrefix.summed)
            let result = try api.sendMetrics(payload, url: url)
            handleSummedEventsResult(result: result)
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

    private func handleSummedEventsResult(result: BacktraceMetricsResult) {
        metricsContainer.clearSummedEvents()
        // TODO: T16698 - Add retry logic
    }

    private func handleUniqueEventsResult(result: BacktraceMetricsResult) {
        // TODO: T16698 - Add retry logic
    }
}
