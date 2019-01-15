//
//  Dispatcher.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 23/12/2018.
//

import Foundation

@objc public protocol DispatcherType {
    @objc func dispatch(_ block: @escaping () -> Void, completion: @escaping () -> Void)
}

@objc open class Dispatcher: NSObject {

    static let operationQueueName = "backtrace.dispatching"
    static let underlyingQueue = DispatchQueue(label: operationQueueName, qos: .background)

    lazy var serialQueue = { () -> OperationQueue in
        let operationQueue = OperationQueue()
        operationQueue.name = Dispatcher.operationQueueName
        operationQueue.underlyingQueue = Dispatcher.underlyingQueue
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()
}

extension Dispatcher: DispatcherType {
    @objc public func dispatch(_ block: @escaping () -> Void, completion: @escaping () -> Void) {
        let blockOperation = BlockOperation(block: block)
        blockOperation.completionBlock = completion
        serialQueue.addOperation(blockOperation)
    }
}
