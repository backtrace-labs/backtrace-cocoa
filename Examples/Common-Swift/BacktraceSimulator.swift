//
//  BacktraceSimulator.swift
//  Backtrace-iOS
//

import UIKit
import Backtrace

protocol BacktraceSimulatorProtocol {
    func showPnPViewController()
}

class BacktraceSimulator {
            
    // MARK: struct ErrorCase
    
    fileprivate struct ErrorCase {
        fileprivate let title: String
        fileprivate let function: CaseFunction
    }
    
    // MARK: Variables
    
    var delegate: BacktraceSimulatorProtocol?
    
    fileprivate typealias CaseFunction = () -> ()
    
    private var availableCases: [ErrorCase] = []
    private var mockView: MockView?
    
    // MARK: Public API
    
    func numberOfCases() -> Int {
        return availableCases.count
    }
    
    func caseTitle(atIndex index: Int) -> String? {
        guard index >= 0 && index < availableCases.count else { return nil }
        return availableCases[index].title
    }
    
    func executeCase(atIndex index: Int) throws {
        guard index >= 0 && index < availableCases.count else { throw "Error Case doesn't exist" }
        let function = availableCases[index].function
        function()
    }
    
    // MARK: Hidden implementation
    
    init() {
        availableCases.append(ErrorCase(title: "PnP Example", function: examplePnP))
        availableCases.append(ErrorCase(title: "Call On nil", function: callOnNil))
        availableCases.append(ErrorCase(title: "Out of Bounds", function: outOfBounds))
        availableCases.append(ErrorCase(title: "IBOutlet is nil", function: ibOutlet))
        availableCases.append(ErrorCase(title: "UI Call on Non Main Thread", function: uiNonMainThread))
        availableCases.append(ErrorCase(title: "Low Memory Pressure", function: lowMemory))
        availableCases.append(ErrorCase(title: "Throw-Catch", function: throwCatch))
        availableCases.append(ErrorCase(title: "Force Unwrap nil", function: forceUnwrapNil))
        availableCases.append(ErrorCase(title: "Type Case Forced", function: typeCastForced))
        availableCases.append(ErrorCase(title: "Divide By Zero", function: divideByZero))
        availableCases.append(ErrorCase(title: "Infinite Loop", function: infiniteLoop))
        availableCases.append(ErrorCase(title: "Live Report", function: liveReport))
        
        let nib = UINib(nibName: "MockView", bundle: Bundle.main)
        mockView = nib.instantiate(withOwner: nil).first as? MockView
    }

    // 1. Non-optional is nil and we call some method
    private func callOnNil() {
        let string: String! = nil
        print(string.count) // Using print to avoid 'unused' warning
    }
    
    // 2. Array index out of bounds
    private func outOfBounds() {
        let array = [""]
        print(array[1]) // Using print to avoid 'unused' warning
    }
    
    // 3. IBOutlet is non-optional and reference is not set
    private func ibOutlet() {
        mockView?.labelNotLinked.text = ""
    }
    
    // 4. Calling UI object not from the main thread
    private func uiNonMainThread() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.mockView?.labelLinked.text = ""
        }
    }
    
    // 5. Low memory error
    private func lowMemory() {
        var wastedMemory: Data = Data()
        let size = 50_000_000
        for _ in 1...10000 {
            let data = Data(repeating: 0, count: size)
            wastedMemory.append(data)
        }
    }
    
    // 6. Throw-catch exception
    private func throwCatch() {
        let string: String? = nil
        do {
            if string == nil {
                throw "String is nil"
            }
        }
        catch {
            print(error)
            BacktraceClient.shared?.send(attachmentPaths: []) { (result) in }
        }
    }
    
    // 7. Force unwrap nil
    private func forceUnwrapNil() {
        let string: String? = nil
        print(string!.count)
    }
    
    // 8. Type cast forced of non compatible types
    private func typeCastForced() {
        let string: String? = ""
        print(string as! Int32) // Using print to avoid 'unused' warning
    }
    
    // 9. Divide by zero
    private func divideByZero() {
        // We can't explicitly divide by zero, as it will be a compilation error.
        // To simulate it in runtime - a closure is defined
        let dividingFunc = { (value: Int) -> Void in
            _ = 100 / value
        }

        dividingFunc(0)
    }
    
    // 10. Infinite loop
    private func infiniteLoop() {
        DispatchQueue.main.sync {
            while(true) {}
        }
    }
    
    // 11. Send live report (keeping from previous examples)
    private func liveReport() {
        let exception = NSException(name: NSExceptionName.characterConversionException,
                                    reason: "custom reason",
                                    userInfo: ["testUserInfo": "tests"])

        BacktraceClient.shared?.send(exception: exception,
                                     attachmentPaths: [],
                                     completion: { (result: BacktraceResult) in
            print(result)
        })
    }
    
    private func examplePnP() {
        delegate?.showPnPViewController()
    }
}

extension String: Error {}
