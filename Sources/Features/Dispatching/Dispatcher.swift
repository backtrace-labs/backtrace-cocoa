import Foundation

final class Dispatcher {

    static let operationQueueName = "backtrace.dispatching"
    static let underlyingQueue = DispatchQueue(label: operationQueueName, qos: .background)
    private let lifecycleLock = NSLock()
    private var shutdownRequested = false

    lazy var workingQueue = { () -> OperationQueue in
        let operationQueue = OperationQueue()
        operationQueue.name = Dispatcher.operationQueueName
        operationQueue.underlyingQueue = Dispatcher.underlyingQueue
        operationQueue.maxConcurrentOperationCount = 10
        return operationQueue
    }()
}

extension Dispatcher: Dispatching {
    func dispatch(_ block: @escaping () -> Void, completion: @escaping () -> Void) {
        lifecycleLock.lock()
        guard !shutdownRequested else {
            lifecycleLock.unlock()
            return
        }
        let blockOperation = BlockOperation(block: block)
        blockOperation.completionBlock = completion
        workingQueue.addOperation(blockOperation)
        lifecycleLock.unlock()
    }

    func shutdown() {
        lifecycleLock.lock()
        guard !shutdownRequested else {
            lifecycleLock.unlock()
            return
        }
        shutdownRequested = true
        workingQueue.cancelAllOperations()
        lifecycleLock.unlock()
    }
}
