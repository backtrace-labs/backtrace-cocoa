//
//  SimulatorCaseCell.swift
//  Backtrace
//

import UIKit

class SimulatorCaseCell : UITableViewCell {
    
    @IBOutlet weak var titleLabel: UILabel!
    
    func setTitle(_ title: String?) {
        titleLabel.text = title
    }
    
    func setTextColor(_ color: UIColor) {
        titleLabel.textColor = color
    }
}
