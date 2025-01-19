//
//  TableDataSortComparator.swift
//  Searchlight
//
//  Created by Ravel Antunes on 8/7/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation

// This is a struct that will be used to compare two rows in a table data set.
// It is initialized and used as NSSortDescriptor in the NSTableViews.
// This is required as the root object isn't really what we are directly comparing,
// and instead we are comparing child objects.
struct TableDataSortComparator: SortComparator, Equatable {
    var order: SortOrder = .forward
    
    let columnKey: String
    let columnIndex: Int
    
    init(columnKey: String, columnIndex: Int, order: SortOrder) {
        self.columnKey = columnKey
        self.columnIndex = columnIndex
        self.order = order
    }

    func compare(_ lhs: SelectResultRow, _ rhs: SelectResultRow) -> ComparisonResult {
        // TODO: handle better scenarios for null, unsuported, etc, since it will compare their string representation here
        return lhs.cells[columnIndex].value.stringRepresentation.compare(rhs.cells[columnIndex].value.stringRepresentation)
    }
    
    static func == (lhs: TableDataSortComparator, rhs: TableDataSortComparator) -> Bool {
        return lhs.columnKey == rhs.columnKey && lhs.columnIndex == rhs.columnIndex && lhs.order == rhs.order
    }
}
