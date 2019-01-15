//
//  ViewController.swift
//  Example-iOS
//
//  Created by Marcin Karmelita on 08/12/2018.
//

import UIKit
import Backtrace

struct CustomError: Error {

}
class ViewController: UIViewController {
    @IBOutlet weak var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.text = BacktraceClient.shared.pendingCrashReport
    }

    @IBAction func liveReportAction(_ sender: Any) {
        let report = BacktraceClient.shared.generateLiveReport()
        textView.text = report
        BacktraceClient.shared.send(CustomError())
    }

    @IBAction func crashAppAction(_ sender: Any) {
        let items = [String]()
        _ = items[1]
    }
}
