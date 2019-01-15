//
//  NetworkClientType.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 22/12/2018.
//

import Foundation

@objc public protocol NetworkClientType {
    typealias ResponseCompletion = (_ urlResponse: URLResponse?, _ responseError: Error?) -> Void
    func send(_ data: Data, completion: ResponseCompletion?)
    func send(_ report: Data) throws
}
