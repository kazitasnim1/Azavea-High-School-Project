//
//  PeripheralTableViewCell.swift
//  Senior Robot Project
//
//  Created by Kazi tasnim on 5/22/18.
//  Copyright © 2018 Kazi Tasnim. All rights reserved.
//

import UIKit

class PeripheralTableViewCell: UITableViewCell {
    
    @IBOutlet weak var peripheralLabel: UILabel!
    @IBOutlet weak var rssiLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        // Configure the view for the selected state
    }
    
}
