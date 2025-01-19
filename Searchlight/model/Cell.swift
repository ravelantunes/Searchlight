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
}

struct Cell: Equatable {

    let column: Column
    let value: CellValueRepresentation
    let position: Int // same as Column index
    var isDirty: Bool = false // Used as a mechanism to determine if cell value was updated
        
    static func == (lhs: Cell, rhs: Cell) -> Bool {
        return lhs.column == rhs.column && lhs.position == rhs.position
    }
    
    // Returns a string representation of the cell's value, taking into consideration the type
    // For example, if it's a string, it will already return the value enclosed in single quotes
    // TODO: review if this is still needed, or we can just handle within the enum (1/11/25)
    func sqlValueString() -> String {
        // TODO: handle types
        
        if value == .null {
            return "NULL"
        }
        
//        if self.column.type == "string" {
//            return "'\(value)'"
//        }
//        return value
        return "'\(value.stringRepresentation)'"
    }
}
