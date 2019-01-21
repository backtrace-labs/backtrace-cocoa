//
//  BacktraceClientConfiguration.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 17/01/2019.
//

import Foundation

/// Backtrace client configuration settings.
@objc public class BacktraceClientConfiguration: NSObject {
    
    /// Client's credentials.
    @objc public let credentials: BacktraceCredentials
    
    /// Client's custom attributes.
    @objc public var clientAttributes: [String: Any]  = [:]
    
    /// Number of recordds send per one minute.
    @objc public var reportPerMin: Int = 3
    
    /// Produces Backtrace client configuration settings.
    ///
    /// - Parameter credentials: Backtrace server API credentials.
    @objc public init(credentials: BacktraceCredentials) {
        self.credentials = credentials
    }
}
