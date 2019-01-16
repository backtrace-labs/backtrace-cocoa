//
//  BacktraceTests.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 17/12/2018.
//

import Nimble
import Quick
@testable import Backtrace

final class BacktraceTests: QuickSpec {
    
    override func spec() {
        describe("Crash reporter") {
            let crashReporter = CrashReporter()
            it("generates live report", closure: {
                expect { try crashReporter.generateLiveReport() }
                    .toNot(throwError())
            })
            it("generate live report 100 times", closure: {
                for _ in 0...100 {
                    expect{ try crashReporter.generateLiveReport() }
                        .toNot(throwError())
                }
            })
        }
    }
}
