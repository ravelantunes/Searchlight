//
//  TableViewAppKit+NSTableView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 9/14/25.
//
//  Copyright (c) 2025 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import AppKit

extension TableViewAppKit: NSTableViewDelegate, NSTableViewDataSource {
    
    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        return 300
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = data.columns.first(where: { $0.name == tableColumn?.identifier.rawValue }) else {
            fatalError("Column not found. This should not happen")
        }
                
        guard let cellView = tableView.makeView(withIdentifier: DatabaseTableViewCell.CellIdentifier, owner: self) as? DatabaseTableViewCell
            ?? DatabaseTableViewCell.loadFromNib(api: pgApi!, delegate: self)
        else {
            fatalError("Cell view is nil")
        }
        
        let isEditable = {
            if case .updating(let coordinate) = currentEditMode {
                return coordinate.row == row
            }
            if currentEditMode == .inserting {
                return true
            }
            return false
        }()
        
        let cellContent = {
            if self.currentEditMode == .inserting && row == self.data.rows.count {
                return Cell(column: column, value: .actual(""), position: column.position)
            }
            return self.getCell(coordinate: Coordinate(row: row, column: column.position))!
        }()
        
        cellView.setContent(content: cellContent, editable: isEditable)
        cellView.delegate = self
        return cellView
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return true
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        let selectedIndex = tableView.selectedRowIndexes
        
        // Check if selected indexes are empty
        // TODO: Review why I needed this. It is calling submitEditing on a delete animation
//        if selectedIndex.count == 0 {
//            submitEditing()
//            return
//        }
    }
    
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard tableView.sortDescriptors.count > 0 else {
            return
        }
            
        // TODO: I think there's a crash when changing tables with sortDescriptors selected, because the table column names are not the same
        let sortDescriptor = tableView.sortDescriptors.first!
        let columnName = sortDescriptor.key!
        let ascending = sortDescriptor.ascending
        let columnIndex = data.columns.firstIndex { $0.name == columnName }
        let sort = TableDataSortComparator(columnKey: columnName, columnIndex: columnIndex!, order: ascending ? .forward : .reverse)
        
        self.appKitDelegate?.onSort(sortDescriptor: [sort])
    }
}
