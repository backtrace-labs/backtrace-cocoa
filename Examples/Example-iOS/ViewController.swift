import UIKit
import Backtrace

class ViewController: UIViewController {
    
    static var wastedMemory: Data = Data()
    
    @IBOutlet weak var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    @IBAction func outOfMemoryReportAction(_ sender: Any) {
        for _ in 1...10000 {
            let data = Data(repeating: 0, count: 500_000)
            ViewController.wastedMemory.append(data)
        }
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
