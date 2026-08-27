import Foundation

final class BacktraceNetworkClient {
    let urlSession: URLSession
    let reachability = NetworkReachability()
    private let lifecycleLock = NSLock()
    private var activeTasks: [UUID: URLSessionDataTask] = [:]
    private var shutdownRequested = false
    private let afterTransportCompletion: (() -> Void)?

    init(urlSession: URLSession,
         afterTransportCompletion: (() -> Void)? = nil) {
        self.urlSession = urlSession
        self.afterTransportCompletion = afterTransportCompletion
    }

    func send(request: URLRequest) throws -> BacktraceHttpResponse {
        lifecycleLock.lock()
        let canStart = !shutdownRequested
        lifecycleLock.unlock()
        guard canStart else {
            throw URLError(.cancelled)
        }

        let taskIdentifier = UUID()
        let response = self.urlSession.sync(
            request,
            taskCreated: { [weak self] task in
                self?.register(task, identifier: taskIdentifier)
            },
            taskCompleted: { [weak self] in
                self?.removeTask(identifier: taskIdentifier)
            })
        afterTransportCompletion?()

        // Once URLSession has produced an HTTP response, that response is authoritative even when shutdown races the synchronous caller.
        // Discarding it here would prevent the submission coordinator from recording an accepted or permanently rejected report before the repository is quiesced.
        if let urlResponse = response.urlResponse {
            return BacktraceHttpResponse(httpResponse: urlResponse, responseData: response.responseData)
        }

        lifecycleLock.lock()
        let wasShutdown = shutdownRequested
        lifecycleLock.unlock()
        if wasShutdown {
            throw NetworkError.cancelled
        }

        if let responseError = response.responseError {
            throw NetworkError.connectionError(responseError)
        }
        throw HttpError.unknownError
    }

    func isNetworkAvailable() -> Bool {
        return reachability.isReachable
    }

    internal var isShutdown: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return shutdownRequested
    }

    /// Prevents new requests and cancels every URLSession task owned by this SDK client.
    /// Cancellation is deliberately non-blocking: task completions release synchronous callers without making native bridge shutdown wait on the transport.
    internal func shutdown() {
        lifecycleLock.lock()
        guard !shutdownRequested else {
            lifecycleLock.unlock()
            return
        }
        shutdownRequested = true
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        lifecycleLock.unlock()

        tasks.forEach { $0.cancel() }
    }

    private func register(_ task: URLSessionDataTask, identifier: UUID) {
        lifecycleLock.lock()
        if shutdownRequested {
            lifecycleLock.unlock()
            task.cancel()
            return
        }
        activeTasks[identifier] = task
        lifecycleLock.unlock()
    }

    private func removeTask(identifier: UUID) {
        lifecycleLock.lock()
        activeTasks.removeValue(forKey: identifier)
        lifecycleLock.unlock()
    }
}

extension BacktraceNetworkClient {

    func sendMetrics(request: URLRequest) {
        let taskIdentifier = UUID()
        let task = self.urlSession.dataTask(with: request,
                            completionHandler: { [weak self] (_, _, responseError) in
            self?.removeTask(identifier: taskIdentifier)
            // TODO: T16698 - Add retry logic
            if responseError != nil, self?.isShutdown == false {
                BacktraceLogger.error("Metrics submission failed")
            }
        })

        lifecycleLock.lock()
        guard !shutdownRequested else {
            lifecycleLock.unlock()
            task.cancel()
            return
        }
        activeTasks[taskIdentifier] = task
        lifecycleLock.unlock()
        task.resume()
    }
}
