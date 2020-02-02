import UIKit
import Backtrace

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
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

