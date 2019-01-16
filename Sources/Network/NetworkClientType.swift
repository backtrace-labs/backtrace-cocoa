//
//  NetworkClientType.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 22/12/2018.
//

import Foundation

protocol NetworkClientType {
    func send(_ report: Data) throws -> BacktraceResponse
}
