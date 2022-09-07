//
//  ViewController.swift
//  Backtrace
//

import UIKit

class ViewController: UIViewController {
        
    @IBOutlet weak var tableView: UITableView!
    
    let simulator: BacktraceSimulatorProtocol = BacktraceSimulator()
}

extension ViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        do {
            try simulator.executeCase(atIndex: indexPath.row)
        }
        catch {
            let alert = UIAlertController(title: "Can't execute command",
                                          message: error as? String ?? "",
                                          preferredStyle: .alert)
            present(alert, animated: true)
        }
    }
    
#if os(tvOS)
    
    func tableView(_ tableView: UITableView,
                   didUpdateFocusIn context: UITableViewFocusUpdateContext,
                   with coordinator: UIFocusAnimationCoordinator) {
        
        if let prevIndexPath = context.previouslyFocusedIndexPath {
            let prevCell = tableView.cellForRow(at: prevIndexPath) as? SimulatorCaseCell
            prevCell?.setTextColor(.white)
        }
        
        if let nextIndexPath = context.nextFocusedIndexPath {
            let nextCell = tableView.cellForRow(at: nextIndexPath) as? SimulatorCaseCell
            nextCell?.setTextColor(.black)
        }
    }

#endif
}

extension ViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return simulator.numberOfCases()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let title = simulator.caseTitle(atIndex: indexPath.row)
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "CaseCell") as! SimulatorCaseCell
        cell.setTitle(title)

        return cell
    }
}
