import UIKit
import Backtrace

class ViewController: UIViewController {
    @IBOutlet weak var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
    }

    @IBAction func liveReportAction(_ sender: Any) {

        // Send NSException
        let exception = NSException(name: NSExceptionName.characterConversionException, reason: "custom reason", userInfo: ["testUserInfo": "tests"])
        BacktraceClient.shared?.send(exception: exception, attachmentPaths: [], completion: { (result: BacktraceResult) in
            print(result)
        })
    }

    @IBAction func crashAppAction(_ sender: Any) {
        let items = [String]()
        _ = items[1]
    }
}
