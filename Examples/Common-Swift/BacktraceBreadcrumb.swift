//
//  BacktraceBreadcrumb.swift
//  Example-iOS-PnP
//

import Foundation
import Backtrace

fileprivate func randomName() -> String {
    return String.init(format: "%f", Date.timeIntervalSinceReferenceDate)
}

class BacktraceBreadcrumb {

    // MARK: Levels
    static var Debug: BacktraceBreadcrumb {
        return BacktraceBreadcrumb(name: randomName(), level: .debug)
    }

    static var Info: BacktraceBreadcrumb {
        return BacktraceBreadcrumb(name: randomName(), level: .info)
    }

    static var Warning: BacktraceBreadcrumb {
        return BacktraceBreadcrumb(name: randomName(), level: .warning)
    }

    static var Error: BacktraceBreadcrumb {
        return BacktraceBreadcrumb(name: randomName(), level: .error)
    }

    static var Fatal: BacktraceBreadcrumb {
        return BacktraceBreadcrumb(name: randomName(), level: .fatal)
    }

    // MARK: Types
    var Manual: BacktraceBreadcrumb {
        type = .manual
        return self
    }

    var Log: BacktraceBreadcrumb {
        type = .log
        return self
    }

    var Navigation: BacktraceBreadcrumb {
        type = .navigation
        return self
    }

    var HTTP: BacktraceBreadcrumb {
        type = .http
        return self
    }

    var System: BacktraceBreadcrumb {
        type = .system
        return self
    }

    var User: BacktraceBreadcrumb {
        type = .user
        return self
    }

    var Configuration: BacktraceBreadcrumb {
        type = .configuration
        return self
    }

    // MARK: private
    private var name: String
    private var type: BacktraceBreadcrumbType
    private var level: BacktraceBreadcrumbLevel
    private var values: [String:String]
    
    init(name: String = "",
         type: BacktraceBreadcrumbType = .user,
         level: BacktraceBreadcrumbLevel = .debug,
         values: [String:String] = [:]) {
        self.name = name
        self.type = type
        self.level = level
        self.values = values
    }
    
    // MARK: Configuration
    func setValues(_ newValues: [String:String]) -> BacktraceBreadcrumb {
        self.values = newValues
        return self
    }
    
    func addValue(_ newValue: String, forKey key: String) -> BacktraceBreadcrumb {
        self.values[key] = newValue
        return self
    }
    
    // MARK: Saving
    func commit() {
        _ = BacktraceClient.shared?.addBreadcrumb(self.name,
                                                  attributes: self.values,
                                                  type: self.type,
                                                  level: self.level)
    }
}
