//
//  Coordinate.swift
//  Searchlight
//
//  Created by Ravel Antunes on 9/14/25.
//
//  Copyright (c) 2025 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//


// Similar to IndexPath, representing row/column pair, but simpler to use
struct Coordinate: Equatable {
    let row: Int
    let column: Int?
    
    var hasValidRow: Bool {
        row >= 0
    }
}
