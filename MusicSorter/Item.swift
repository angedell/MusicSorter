//
//  Item.swift
//  MusicSorter
//
//  Created by Angelo Dell Acqua on 10/18/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
