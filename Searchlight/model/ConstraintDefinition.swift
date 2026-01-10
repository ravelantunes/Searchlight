//
//  ConstraintDefinition.swift
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

/// Types of PostgreSQL constraints
enum ConstraintType: String, CaseIterable {
    case primaryKey = "PRIMARY KEY"
    case foreignKey = "FOREIGN KEY"
    case unique = "UNIQUE"
    case check = "CHECK"
    case exclusion = "EXCLUSION"
}

// Represents a database constraint
struct ConstraintDefinition: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let constraintType: ConstraintType
    let columns: [String]
    let checkExpression: String?
    let foreignKeyReference: ForeignKeyReference?
    let onDelete: String?
    let onUpdate: String?

    init(name: String, constraintType: ConstraintType, columns: [String],
         checkExpression: String? = nil, foreignKeyReference: ForeignKeyReference? = nil,
         onDelete: String? = nil, onUpdate: String? = nil) {
        self.id = name
        self.name = name
        self.constraintType = constraintType
        self.columns = columns
        self.checkExpression = checkExpression
        self.foreignKeyReference = foreignKeyReference
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }
}
