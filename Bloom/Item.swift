//
//  Item.swift
//  Bloom
//
//  Created by Emily Du on 25/9/2026.
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
