import UIKit
import Backtrace

class ViewController: UIViewController {

    static var wastedMemory: Data = Data()

    @IBOutlet weak var textView: UITextView!

    private var isTextViewHidden = false

    override func viewDidLoad() {
        super.viewDidLoad()

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

    // MARK: - TestFairy Feature Actions

    /// Convenience accessor for the concrete BacktraceClient (needed for new feature protocols).
    private var client: BacktraceClient? {
        BacktraceClient.shared as? BacktraceClient
    }

    @IBAction func showFeedbackAction(_ sender: Any) {
        client?.showFeedbackForm()
    }

    @IBAction func logMessageAction(_ sender: Any) {
        let message = "Test log from Example-iOS at \(Date())"
        client?.log(message, level: .info)
        appendToTextView("Logged: \(message)")
    }

    @IBAction func toggleViewHidingAction(_ sender: Any) {
        isTextViewHidden.toggle()
        if isTextViewHidden {
            client?.hideView(textView)
            appendToTextView("[Session Replay] textView is now HIDDEN from screenshots")
        } else {
            client?.unhideView(textView)
            appendToTextView("[Session Replay] textView is now VISIBLE in screenshots")
        }

        if let button = sender as? UIButton {
            button.setTitle(isTextViewHidden ? "unhide view from replay" : "hide view from replay", for: .normal)
        }
    }

    @IBAction func sendReportWithAttachmentsAction(_ sender: Any) {
        // Send a live report — log capture, vitals, and session replay attachments are
        // automatically included by the SDK when those features are enabled.
        BacktraceClient.shared?.send(message: "Manual report with all feature attachments",
                                     attachmentPaths: [],
                                     completion: { [weak self] (result: BacktraceResult) in
            DispatchQueue.main.async {
                self?.appendToTextView("Report sent: \(result.backtraceStatus)")
            }
            print("Report with attachments result: \(result)")
        })
        appendToTextView("Sending report with feature attachments...")
    }

    // MARK: - Helpers

    private func appendToTextView(_ text: String) {
        let current = textView.text ?? ""
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        textView.text = current + "[\(timestamp)] \(text)\n"
        let bottom = NSRange(location: textView.text.count - 1, length: 1)
        textView.scrollRangeToVisible(bottom)
    }
}
