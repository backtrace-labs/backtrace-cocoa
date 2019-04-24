import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func crashButtonTapped(_ sender: Any) {
        let items = [String]()
        _ = items[1]
    }
}

