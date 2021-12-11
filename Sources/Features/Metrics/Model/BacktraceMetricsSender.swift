import Foundation

final class BacktraceMetricsSender {
    
    private let api: BacktraceApi
    private let metricsContainer: BacktraceMetricsContainer
    private let settings: BacktraceMetricsSettings
    
    static let defaultBaseUrl = "https://events.backtrace.io/api"
    private let baseUrl: String
        
    enum MetricsUrlPrefix: CustomStringConvertible {
      case Summed
      case Unique
      
      var description : String {
        switch self {
        case .Summed: return "summed-events"
        case .Unique: return "unique-events"
        }
      }
    }
    
    init(api: BacktraceApi, metricsContainer: BacktraceMetricsContainer, settings: BacktraceMetricsSettings) {
        self.api = api
        self.metricsContainer = metricsContainer
        self.settings = settings
        self.baseUrl = BacktraceMetricsSender.defaultBaseUrl
    }
    
    func enable() {
        sendStartupEvents()
    }
    
    private func sendStartupEvents() {
        sendStartupSummedEvent()
        sendStartupUniqueEvent()
    }
    
    private func sendStartupUniqueEvent() {
        
    }
    
    private func sendStartupSummedEvent() {
        let payload = metricsContainer.getSummedEventsPayload()
        
        do {
            let url = try getSubmissionUrl(urlPrefix: MetricsUrlPrefix.Summed)
            try api.sendMetrics(payload, url: url)
        } catch {
            BacktraceLogger.error(error)
        }
    }
    
    func getSubmissionUrl(urlPrefix: MetricsUrlPrefix) throws -> URL {
        let token = try api.credentials.getSubmissionToken()
        let universe = try api.credentials.getUniverseName()
        
        let urlString = self.baseUrl + "/" + urlPrefix.description + "/submit?token=" + token + "&universe=" + universe
        
        guard let url = URL(string: urlString) else {
            throw BacktraceUrlParsingError.InvalidInput(urlString)
        }
        return url
    }
}
