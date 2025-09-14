//
//  SelectResult.swift
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

struct SelectResult: Identifiable {
        
    let id: UUID
    let columns: [Column]
    let rows: [SelectResultRow]
    var tableName: String?
    
    init(id: UUID = UUID(),
           columns: [Column],
           rows: [SelectResultRow],
           tableName: String? = nil) {
          self.id = id
          self.columns = columns
          self.rows = rows
          self.tableName = tableName
      }
    
    func dataAsDictionary() -> [[String: String]] {
        return self.rows.map { row in
            var dict = [String: String]()
            for (i, cell) in row.cells.enumerated() {
                dict[self.columns[i].name] = cell.value.stringRepresentation
            }
            return dict
        }
    }
    
    subscript(row: Int) -> SelectResultRow {
        get {
            return self.rows[row]
        }
    }
    
    func column(withName name: String) -> Column? {
        guard let columnIndex = self.columnIndex(withName: name) else {
            return nil
        }
        
        return self.columns[columnIndex]
    }
    
    func columnIndex(withName name: String) -> Int? {
        return self.columns.firstIndex { column in
            return column.name == name
        }
    }
    
    func cell(rowAt row: Int, withColumnName: String) -> Cell? {
        guard let columnIndex = self.columnIndex(withName: withColumnName) else {
            return nil
        }
        
        if row >= self.rows.count {
            return nil
        }
    
        return self.rows[row].cells[columnIndex]
    }
}

struct SelectResultRow: Identifiable, Comparable, Hashable {
    let id: String
    let cells: [Cell]
    let isEmptyRow: Bool
    
    init(id: String, cells: [Cell], isEmptyRow: Bool = false) {
        self.id = id
        self.cells = cells
        self.isEmptyRow = isEmptyRow
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    subscript(columnName: String) -> Cell {
        get {
            let columnIndex = self.cells.firstIndex { cell in
                return cell.column.name == columnName
            }
            
            return self.cells[columnIndex!]
        }
    }
    
    static func < (lhs: SelectResultRow, rhs: SelectResultRow) -> Bool {
        return lhs.id < rhs.id
    }
    
    static func EmptySelectResultRow() -> SelectResultRow {
        return SelectResultRow(id: "template", cells: [], isEmptyRow: true)
    }
}
