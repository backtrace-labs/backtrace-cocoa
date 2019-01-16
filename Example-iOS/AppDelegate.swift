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
        BacktraceClient.shared.register(endpoint: "https://yolo.sp.backtrace.io:6098",
                                        token: "b06c6083414bf7b8e200ad994c9c8ea5d6c8fa747b6608f821278c48a4d608c3")
        return true
    }
}
