//
//  BacktraceCrashLoop.swift
//  Backtrace
//

import Foundation

@objc internal class BacktraceCrashLoop: NSObject {

    @objc internal static func LogDebug(_ message: String = "") {

        /*  Routed logging here to add prefix for more convenient filtering of
            BTCLD logs in Xcode's outputs
         */
        let prefix = "BT CL: "

        /*  Since Backtrace is not enabled during Crash Loop detection,
            BacktraceLogger is also not set up, so it doesn't log messages
            => using native 'print' here
         */
        print(prefix + message)
    }
}
