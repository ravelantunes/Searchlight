//
//  EditingMode.swift
//  Searchlight
//
//  Created by Ravel Antunes on 9/14/25.
//
//  Copyright (c) 2025 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

// Used to represent state of tableView
enum EditingMode: Equatable {
    case none
    case inserting
    case updating(coordinate: Coordinate)
}
