import Foundation

final class BacktraceMetricsSender {

    private let api: BacktraceApi
    private let metricsContainer: BacktraceMetricsContainer
    private let settings: BacktraceMetricsSettings

    private let baseUrlString: String
    private let queue = DispatchQueue(label: "com.backtrace.metrics", qos: .background)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let lifecycleLock = NSLock()
    private var shutdownRequested = false

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
        self.queue.setSpecific(key: queueKey, value: true)
    }

    func enable() {
        guard !isShutdown else { return }
        queue.async { [weak self] in
            guard let self = self, !self.isShutdown else { return }
            self.sendStartupEvents()
        }
    }

    internal var isShutdown: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return shutdownRequested
    }

    internal func shutdown() {
        lifecycleLock.lock()
        shutdownRequested = true
        lifecycleLock.unlock()

        // Metrics URL/payload preparation is finite and its transport API is asynchronous.
        // Drain only this queue so no startup metrics work continues after Disable returns;
        // never wait reentrantly if shutdown is triggered from the sender itself.
        if DispatchQueue.getSpecific(key: queueKey) != true {
            queue.sync {}
        }
    }

    private func sendStartupEvents() {
        guard !isShutdown else { return }
        sendStartupSummedEvent()
        guard !isShutdown else { return }
        sendStartupUniqueEvent()
    }

    private func sendStartupUniqueEvent() {
        sendUniqueEvent()
    }

    private func sendStartupSummedEvent() {
        sendSummedEvent()
    }

    private func sendUniqueEvent() {
        guard !isShutdown else { return }
        let payload = metricsContainer.getUniqueEventsPayload()

        do {
            let url = try getSubmissionUrl(urlPrefix: MetricsUrlPrefix.unique)
            guard !isShutdown else { return }
            api.sendMetrics(payload, url: url)
        } catch {
            BacktraceLogger.error("Unable to prepare unique metrics submission")
        }
    }

    private func sendSummedEvent() {
        guard !isShutdown else { return }
        let payload = metricsContainer.getSummedEventsPayload()
        metricsContainer.clearSummedEvents()

        do {
            let url = try getSubmissionUrl(urlPrefix: MetricsUrlPrefix.summed)
            guard !isShutdown else { return }
            api.sendMetrics(payload, url: url)
        } catch {
            BacktraceLogger.error("Unable to prepare summed metrics submission")
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
