import Foundation

final class BacktraceMetricsSender {
    
    private let api: BacktraceApi
    private let metricsContainer: BacktraceMetricsContainer
    private let settings: BacktraceMetricsSettings
    
    init(api: BacktraceApi, metricsContainer: BacktraceMetricsContainer, settings: BacktraceMetricsSettings) {
        self.api = api
        self.metricsContainer = metricsContainer
        self.settings = settings
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
        
    }
    
    
}
