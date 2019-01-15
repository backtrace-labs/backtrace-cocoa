//
//  AppDelegate.swift
//  Example-iOS
//
//  Created by Marcin Karmelita on 08/12/2018.
//

import UIKit
import Backtrace

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        BacktraceClient.shared.register(endpoint: "",
                                        token: "")
        return true
    }
}
