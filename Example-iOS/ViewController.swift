
import UIKit
import Backtrace

struct CustomError: Error {

}

class ViewController: UIViewController {
    @IBOutlet weak var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
    }

    @IBAction func liveReportAction(_ sender: Any) {
        BacktraceClient.shared.send(CustomError())
        
        let exception = NSException(name: NSExceptionName(rawValue: "backtrace.exception.name"), reason: "backtrace.exception.reason", userInfo: nil)
        BacktraceClient.shared.send(exception: exception) { (result) in
            print(result.message)
        }
    }

    @IBAction func crashAppAction(_ sender: Any) {
        let items = [String]()
        _ = items[1]
    }
}
