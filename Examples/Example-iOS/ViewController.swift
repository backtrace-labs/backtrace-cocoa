import UIKit
import Backtrace

class ViewController: UIViewController {
    
    static var wastedMemory: Data = Data()
    
    @IBOutlet weak var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        textView.text = "BadEvents: " + BacktraceClient.consecutiveCrashesCount().description
        + "\nIs Safe to Launch: " + (BacktraceClient.isInSafeMode() ? "FALSE" : "TRUE")
    }
    
    @IBAction func outOfMemoryReportAction(_ sender: Any) {
        // The trick is: to aggressively take up memory but not allocate a block too large to cause a crash
        // This is obviously device dependent, so the 500k may have to be tweaked
        let size = 500_000
        for _ in 1...10000 {
            let data = Data(repeating: 0, count: size)
            ViewController.wastedMemory.append(data)
        }
        // Or if all that fails, just force a memory warning manually :)
        UIControl().sendAction(Selector(("_performMemoryWarning")), to: UIApplication.shared, for: nil)
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
