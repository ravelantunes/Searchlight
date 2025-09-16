//
//  Column.swift
//  Searchlight
//
//  Created by Ravel Antunes on 6/2/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation
import AppKit

// Postgres Types:
// A    Array types
// B    Boolean types
// C    Composite types
// D    Date/time types
// E    Enum types
// G    Geometric types
// I    Network address types
// N    Numeric types
// P    Pseudo-types
// R    Range types
// S    String types
// T    Timespan types
// U    User-defined types
// V    Bit-string types
// X    unknown type
// Z    Internal-use types
struct Column: Equatable, Identifiable, Comparable, Hashable {
    let id: String
    let name: String
    let type: String
    let typeName: String
    let typeCategory: String
    
    // Interal, 0-index contiguous position of the row. Not to be confused with pg internal ordinal_position
    let position: Int
    let foreignTableName: String?
    let foreignColumnName: String?
    let foreignSchemaName: String?
    var cells: [Cell] = []
    
    init(name: String, type: String, typeName: String, typeCategory: String, position: Int, foreignSchemaName: String?, foreignTableName: String?, foreignColumnName: String?) {
        self.name = name
        self.type = type
        self.typeName = typeName
        self.typeCategory = typeCategory
        self.position = position
        self.foreignSchemaName = foreignSchemaName
        self.foreignTableName = foreignTableName
        self.foreignColumnName = foreignColumnName
        self.id = self.name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func < (lhs: Column, rhs: Column) -> Bool {
        lhs.name < rhs.name
    }
    
    func typeDisplayName() -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 10)
        let mutableAttributedString = switch typeName {
        case "timestamp":
            NSMutableAttributedString(string: "🗓️", attributes: [.font: font])
        case "uuid":
            NSMutableAttributedString(string: "uuid", attributes: [.font: font, .foregroundColor: NSColor.systemTeal])
        case "varchar":
            NSMutableAttributedString(string: "✏️", attributes: [.font: font])
        case "bool":
            NSMutableAttributedString(string: "✅", attributes: [.font: font])
        case "time":
            NSMutableAttributedString(string: "⏰", attributes: [.font: font])
        case "int4", "int8":
            NSMutableAttributedString(string: "123", attributes: [.font: font, .foregroundColor: NSColor.systemGreen])
        case "json":
            NSMutableAttributedString(string: "{}", attributes: [.font: font, .foregroundColor: NSColor.systemBlue])
        default:
            NSMutableAttributedString(string: typeName, attributes: [.font: font, .foregroundColor: NSColor.systemOrange])
        }
                
        return mutableAttributedString
    }
    
    // For certain columns there might be additional info worth showing. ie.: foreign column this points to
    func additionalDisplayInfo() -> NSAttributedString? {
        if foreignTableName != nil {
            let font = NSFont.systemFont(ofSize: 10)
            return NSAttributedString(string: " (→\(foreignTableName!).\(foreignColumnName!))", attributes: [.font: font, .foregroundColor: NSColor.systemGray])
        }
        return nil
    }
    
    // MARK: helpers for type checks
    
    func isNumeric() -> Bool {
        ["int4", "int8"].contains(typeName)
    }
    
    func isDate() -> Bool {
        ["timestamp", "time"].contains(typeName)
    }
}
