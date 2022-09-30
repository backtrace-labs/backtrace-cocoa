import UIKit
import Backtrace

class ViewController: UIViewController {

    @IBOutlet weak var textView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        textView.text = "BadEvents: " + BacktraceClient.consecutiveCrashesCount().description
        + "\nIs Safe to Launch: " + (BacktraceClient.isInSafeMode() ? "FALSE" : "TRUE")
    }
    
    @IBAction func liveReportAction(_ sender: Any) {

        BacktraceClient.shared?.send(attachmentPaths: [], completion: { (result: BacktraceResult) in
            print(result)
        })
    }

    @IBAction func crashButtonTapped(_ sender: Any) {
        let items = [String]()
        _ = items[1]
    }
}

