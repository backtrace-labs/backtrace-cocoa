import UIKit
import Backtrace

class ViewController: UIViewController {
    @IBOutlet weak var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
    }

    @IBAction func liveReportAction(_ sender: Any) {
        BacktraceClient.shared.send { (result) in
            print(result.message)
        }
    }

    @IBAction func crashAppAction(_ sender: Any) {
        let items = [String]()
        _ = items[1]
    }
}
