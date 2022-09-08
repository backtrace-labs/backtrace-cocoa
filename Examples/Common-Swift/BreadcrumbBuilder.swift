//
//  BreadcrumbsBuilder.swift
//  Example-iOS-PnP
//

import Foundation
import Backtrace

class BreadcrumbBuilder {
    
    static var Debug: Breadcrumb {
        return Breadcrumb(name: randomName(), level: .debug)
    }

    static var Info: Breadcrumb {
        return Breadcrumb(name: randomName(), level: .info)
    }

    static var Warning: Breadcrumb {
        return Breadcrumb(name: randomName(), level: .warning)
    }

    static var Error: Breadcrumb {
        return Breadcrumb(name: randomName(), level: .error)
    }

    static var Fatal: Breadcrumb {
        return Breadcrumb(name: randomName(), level: .fatal)
    }
    
    private static func randomName() -> String {
        return String.init(format: "%f", Date.timeIntervalSinceReferenceDate)
    }
}

class Breadcrumb {

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
    
    func setType(_ newType: BacktraceBreadcrumbType) -> Breadcrumb {
        self.type = newType
        return self
    }
    
    func setValues(_ newValues: [String:String]) -> Breadcrumb {
        self.values = newValues
        return self
    }
    
    func addValue(_ newValue: String, forKey key: String) -> Breadcrumb {
        self.values[key] = newValue
        return self
    }
    
    func commit() {
        _ = BacktraceClient.shared?.addBreadcrumb(self.name,
                                                  attributes: self.values,
                                                  type: self.type,
                                                  level: self.level)
    }
}
