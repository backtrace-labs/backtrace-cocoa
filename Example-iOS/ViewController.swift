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
        BacktraceClient.shared.send()
    }

    @IBAction func crashAppAction(_ sender: Any) {
        let items = [String]()
        _ = items[1]
    }
}
