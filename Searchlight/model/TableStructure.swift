//
//  TableStructure.swift
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

/// Represents the complete structure of a database table
struct TableStructure: Identifiable {
    let id = UUID()
    let schemaName: String
    let tableName: String
    var columns: [ColumnDefinition]
    var indexes: [IndexDefinition]
    var constraints: [ConstraintDefinition]
}

/// Represents the current view mode in DatabaseViewer
enum DatabaseViewMode: String, CaseIterable {
    case data = "Data"
    case structure = "Structure"
}
