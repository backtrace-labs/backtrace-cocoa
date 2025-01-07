import Foundation


final class BacktraceMetricsSender: @unchecked Sendable {

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
        // Task to start asynchronous work
        Task {
            await self.sendStartupEvents()
        }
    }

    private func sendStartupEvents() async {
        await sendSummedEvent()
        await sendUniqueEvent()
    }

    private func sendUniqueEvent() async {
        let payload = metricsContainer.getUniqueEventsPayload()

        do {
            let url = try getSubmissionUrl(urlPrefix: MetricsUrlPrefix.unique)
            await api.sendMetrics(payload, url: url)
        } catch {
            await BacktraceLogger.error(error)
        }
    }

    private func sendSummedEvent() async {
        let payload = metricsContainer.getSummedEventsPayload()
        metricsContainer.clearSummedEvents()

        do {
            let url = try getSubmissionUrl(urlPrefix: MetricsUrlPrefix.summed)
            await api.sendMetrics(payload, url: url)
        } catch {
            await BacktraceLogger.error(error)
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
