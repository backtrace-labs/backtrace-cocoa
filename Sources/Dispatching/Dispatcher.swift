
import Foundation

@objc public protocol DispatcherType {
    @objc func dispatch(_ block: @escaping () -> Void, completion: @escaping () -> Void)
}

@objc open class Dispatcher: NSObject {

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

extension Dispatcher: DispatcherType {
    @objc public func dispatch(_ block: @escaping () -> Void, completion: @escaping () -> Void) {
        let blockOperation = BlockOperation(block: block)
        blockOperation.completionBlock = completion
        workingQueue.addOperation(blockOperation)
    }
}
