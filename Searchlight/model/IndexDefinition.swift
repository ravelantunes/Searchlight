//
//  IndexDefinition.swift
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

// Represents a database index
struct IndexDefinition: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let tableName: String
    let columns: [String]
    let isUnique: Bool
    let isPrimaryKey: Bool
    let indexType: String
    let indexDefinition: String

    init(name: String, tableName: String, columns: [String], isUnique: Bool,
         isPrimaryKey: Bool, indexType: String, indexDefinition: String) {
        self.id = name
        self.name = name
        self.tableName = tableName
        self.columns = columns
        self.isUnique = isUnique
        self.isPrimaryKey = isPrimaryKey
        self.indexType = indexType
        self.indexDefinition = indexDefinition
    }
}
