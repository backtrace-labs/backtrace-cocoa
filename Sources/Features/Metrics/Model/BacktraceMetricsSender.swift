import Foundation

final class BacktraceMetricsSender {

    private let api: BacktraceApi
    private let metricsContainer: BacktraceMetricsContainer
    private let settings: BacktraceMetricsSettings

    private let baseUrl: String

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
        self.baseUrl = defaultMetricsBaseUrl
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

        let urlString = self.baseUrl + "/" + urlPrefix.description + "/submit?token=" + token + "&universe=" + universe

        guard let url = URL(string: urlString) else {
            throw BacktraceUrlParsingError.invalidInput(urlString)
        }
        return url
    }

    private func handleSummedEventsResult(result: BacktraceMetricsResult) {
        metricsContainer.clearSummedEvents()

        // TODO: Add the retry logic here
    }

    private func handleUniqueEventsResult(result: BacktraceMetricsResult) {

        // TODO: Add the retry logic here
    }
}
