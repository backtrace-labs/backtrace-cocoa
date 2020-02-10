import Foundation

final class Dispatcher {

    static let operationQueueName = "backtrace.dispatching"
    static let underlyingQueue = DispatchQueue(label: operationQueueName, qos: .background)

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
        let blockOperation = BlockOperation(block: block)
        blockOperation.completionBlock = completion
        workingQueue.addOperation(blockOperation)
    }
}
