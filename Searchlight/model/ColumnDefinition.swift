//
//  ColumnDefinition.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/9/26.
//
//  Copyright (c) 2026 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation

// Extended column information for table structure view
struct ColumnDefinition: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let dataType: String
    let udtName: String
    let ordinalPosition: Int
    let isNullable: Bool
    let columnDefault: String?
    let characterMaximumLength: Int?
    let numericPrecision: Int?
    let numericScale: Int?
    let isPrimaryKey: Bool
    let isForeignKey: Bool
    let foreignKeyReference: ForeignKeyReference?

    init(name: String, dataType: String, udtName: String, ordinalPosition: Int,
         isNullable: Bool, columnDefault: String?, characterMaximumLength: Int?,
         numericPrecision: Int?, numericScale: Int?, isPrimaryKey: Bool = false,
         isForeignKey: Bool = false, foreignKeyReference: ForeignKeyReference? = nil) {
        self.id = name
        self.name = name
        self.dataType = dataType
        self.udtName = udtName
        self.ordinalPosition = ordinalPosition
        self.isNullable = isNullable
        self.columnDefault = columnDefault
        self.characterMaximumLength = characterMaximumLength
        self.numericPrecision = numericPrecision
        self.numericScale = numericScale
        self.isPrimaryKey = isPrimaryKey
        self.isForeignKey = isForeignKey
        self.foreignKeyReference = foreignKeyReference
    }

    // Returns the full type name with length/precision (e.g., "varchar(255)")
    var fullTypeName: String {
        if let maxLength = characterMaximumLength {
            return "\(udtName)(\(maxLength))"
        } else if let precision = numericPrecision, let scale = numericScale, scale > 0 {
            return "\(udtName)(\(precision),\(scale))"
        } else if let precision = numericPrecision, udtName == "numeric" {
            return "\(udtName)(\(precision))"
        }
        return udtName
    }
}

// Reference to a foreign key target
struct ForeignKeyReference: Equatable, Hashable {
    let schemaName: String
    let tableName: String
    let columnName: String
}
