//
//  Cell.swift
//  Searchlight
//
//  Created by Ravel Antunes on 6/8/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation

// Encapsulates the value of a cell, making it safe to determine contents that might be null or unsupported, vs literal strings "NULL".
enum CellValueRepresentation: Equatable {
    case actual(String) // The value property of the cell represents the literal value of the cell
    case null // The cell is Null
    case unsupported // The cell value is unsupported by the client and wasn't parsed
    case unparseable // The cell value is supported, but failed during parsing
    
    // Literal strings that will represent certain value representations
    static let nullString = "NULL"
    static let unsupportedString = "UNSUPPORTED"
    static let unparseableString = "UNPARSEABLE"
    
    var stringRepresentation: String {
        switch self {
        case .actual(let value):
            return value
        case .null:
            return CellValueRepresentation.nullString
        case .unsupported:
            return CellValueRepresentation.unsupportedString
        case .unparseable:
            return CellValueRepresentation.unparseableString
        }
    }
    
    // Returns a string in a way that it can be added to a SQL statement.
    // For example, string values will be enclosed with single-quotes, while null value will be just "NULL"
    var sqlValueString: String {
        switch self {
        case .null:
            return "NULL"
        default:
            return "'\(stringRepresentation)'"
        }
    }
}

struct Cell: Equatable {

    let column: Column
    let value: CellValueRepresentation
    let position: Int // same as Column index
    var isDirty: Bool = false // Used as a mechanism to determine if cell value was updated
        
    static func == (lhs: Cell, rhs: Cell) -> Bool {
        return lhs.column == rhs.column && lhs.position == rhs.position
    }
}
