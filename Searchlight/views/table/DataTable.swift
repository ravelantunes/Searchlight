//
//  DataTable.swift
//  Searchlight
//
//  Created by Ravel Antunes on 7/27/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation
import AppKit
import SwiftUI

// This file has the core implementation of how to handle data from a database table. It handles the connection between SwiftUI and AppKit.
// Naming of classes and components is messy: I struggled to find names that represent table where that is already overused as components of SwiftUI, AppKit, etc.

// Represents something similar to an indexPath, so it can keep reference to specific points in the table
struct Coordinate {
    let row: Int
    let column: Int?
}

class TableViewAppKit: NSView {
    
    @IBOutlet weak var tableView: NSTableView!
    weak var appKitDelegate: TableViewAppKitDelegate?
    
    var data: SelectResult = SelectResult(columns: [], rows: [])
    var sortOrder: [TableDataSortComparator] = []
    var readOnly = true
    
    let tableViewHeader = TableHeaderView()
    var errorPopover: NSView?
    var pgApi: PostgresDatabaseAPI?
    private var isInsertingRow = false
    private var rowBeingEditedIndex: Int?
    
    private var selectedCell: Cell?
    private var selectedRow: SelectResultRow?
    
    // IndexPath of actions being performed. This variable can be set so follow up actions in different methods (ie.: delete, update) knows which index path is being current being actioned on.
    // TODO: move all logic in this class to use this for consistents. Need to refactor rowBeingEditedIndex, selectedCell, Row, etc
    private var actionCoordinate: Coordinate?
    
    // I don't remember why I moved some of this initialization here
    func commonInit() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.action = #selector(tableViewSingleClick(_:))
        tableView.doubleAction = #selector(tableViewDoubleClick(_:))
        tableView.headerView = tableViewHeader
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnResizing = true
    }
    
    @objc func tableViewSingleClick(_ sender: AnyObject) {
        let selectedRowIndex = self.tableView.selectedRow
        if isNewRecordRow(selectedRowIndex) {
            submitEditing()
        }
    }
    
    @objc func tableViewDoubleClick(_ sender: AnyObject) {
        let selectedRow = self.tableView.clickedRow
        actionCoordinate = Coordinate(row: selectedRow, column: nil)        
        prepareInsertRow()
        
        // Prevents callback on empty rows double-click
        if selectedRow > -1 {
            appKitDelegate?.onDoubleClickRow(selectResultRow: data.rows[selectedRow])
        }
    }
    
    @objc func prepareInsertRow() {
        guard !readOnly else { return }
        guard data.tableName != nil else { return }
        
        // Do nothing if already in edit mode
        guard !isInsertingRow else { return }
        
        guard actionCoordinate != nil && actionCoordinate!.row >= 0 else {
            print("insert new row")
            isInsertingRow = true
            rowBeingEditedIndex = data.rows.count
            
            let newRowIndexSet = IndexSet(integer: data.rows.count)
            self.tableView.insertRows(at: newRowIndexSet, withAnimation: .effectGap)
            self.tableView.selectRowIndexes(newRowIndexSet, byExtendingSelection: false)            
            self.tableView.scrollRowToVisible(rowBeingEditedIndex!)
            return
        }
        
        for columnIndex in 0..<self.tableView.numberOfColumns {
            let cell = self.tableView.view(atColumn: columnIndex, row: actionCoordinate!.row, makeIfNecessary: false) as? DatabaseTableViewCell
            cell?.isEditing = true
            
            // Mark the cell as first responder
            if columnIndex == self.tableView.clickedColumn {
                cell?.textField.becomeFirstResponder()
            }
        }
        rowBeingEditedIndex = actionCoordinate!.row
    }
    
    // Removes all the columns in the table and re-creates based on the columns in the data.columns
    func refreshColumns() {
        
        self.tableView.tableColumns.forEach { column in
            self.tableView.removeTableColumn(column)
        }
        
        self.data.columns.enumerated().forEach { index, column in
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.name))
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.name, ascending: true)
            
            let combinedAttributedString = NSMutableAttributedString()
            combinedAttributedString.append(column.typeDisplayName())
            combinedAttributedString.append(NSAttributedString(string: " \(column.name) "))
            if let addtionalInfoAttributedString = column.additionalDisplayInfo() {
                combinedAttributedString.append(NSAttributedString(attributedString: addtionalInfoAttributedString))
            }
            tableColumn.headerCell.attributedStringValue = combinedAttributedString
            tableColumn.headerToolTip = "\(column.typeName)"
            
            // Calculate the size
            let widthOfHeaderText = combinedAttributedString.size().width
            let biggestSizeFromRows = (0..<self.data.rows.count).reduce(widthOfHeaderText + 10.0) { currentMax, index in
                let cell = self.data.cell(rowAt: index, withColumnName: column.name)
                if cell == nil {
                    return 0
                }
                let size = DatabaseTableViewCell.calculateSizeForContent(content: cell!)
                return max(currentMax, size.width)
            }
            tableColumn.width = max(biggestSizeFromRows, 100)

            self.tableView.addTableColumn(tableColumn)
        }
        
        if let sortOrder = self.sortOrder.first {
            let sortDescriptor = NSSortDescriptor(key: sortOrder.columnKey, ascending: sortOrder.order == .forward ? true : false)
            self.tableView.sortDescriptors = [sortDescriptor]
        }
        
        // TODO: adding this here for convenience, but makes more sense to live somwhere, perhaps encapsulate all "refresh" of the view in a single method
        tableViewHeader.data = data
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return data.rows.count + (self.isInsertingRow ? 1 : 0)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        guard !readOnly else { return }
        
        let globalLocation = event.locationInWindow
        let localLocation = tableView.convert(globalLocation, from: nil)
        let clickedRowIndex = tableView.row(at: localLocation)
        let clickedCellIndex = tableView.column(at: localLocation)
        actionCoordinate = Coordinate(row: clickedRowIndex, column: clickedCellIndex)
        
        let isClickingOnARow = clickedRowIndex != -1
        selectedRow = data.rows.indices.contains(clickedRowIndex) ? data.rows[clickedRowIndex] : nil
        selectedCell = selectedRow != nil && selectedRow!.cells.indices.contains(clickedCellIndex) ? selectedRow!.cells[clickedCellIndex] : nil
        
        let menu = NSMenu(title: "Context Menu")
        menu.autoenablesItems = false
                
        let copyValueMenuItem = menu.addItem(withTitle: "Copy Value", action: #selector(copyCellValue), keyEquivalent: "")
        copyValueMenuItem.isEnabled = selectedCell?.value != nil  // Disable copy value if value is null
        let copyAsSQLInsertMenuItem = menu.addItem(withTitle: "Copy as SQL Insert", action: #selector(copyAsSQLInsert), keyEquivalent: "")
        copyAsSQLInsertMenuItem.isEnabled = false
        menu.addItem(NSMenuItem.separator())
        _ = menu.addItem(withTitle: "Insert Row", action: #selector(prepareInsertRow), keyEquivalent: "")
        let duplicateRowMenuItem = menu.addItem(withTitle: "Duplicate Row", action: #selector(duplicateRow), keyEquivalent: "")
        duplicateRowMenuItem.isEnabled = false
        let deleteRowMenuItem = menu.addItem(withTitle: "Delete Row", action: #selector(deleteRow), keyEquivalent: "")
        
        // Disable items that are only relevant in the context of a selected row
        if !isClickingOnARow {
            copyAsSQLInsertMenuItem.isEnabled = false
            copyValueMenuItem.isEnabled = false
            duplicateRowMenuItem.isEnabled = false
            deleteRowMenuItem.isEnabled = false
        }

        NSMenu.popUpContextMenu(menu, with: event, for: tableView)
    }
    
    @objc func cancelEditing() {
        if !isInsertingRow {
            for columnIndex in 0..<self.tableView.numberOfColumns {
                let cell = self.tableView.view(atColumn: columnIndex, row: rowBeingEditedIndex!, makeIfNecessary: false) as? DatabaseTableViewCell
                cell?.isEditing = true
                
                // Mark the cell as first responder
                if columnIndex == self.tableView.clickedColumn {
                    cell?.textField.becomeFirstResponder()
                }
            }
        }
        rowBeingEditedIndex = nil
        isInsertingRow = false
        tableView.reloadData()
    }
    
    func submitEditing() {
        guard let rowBeingEditedIndex = rowBeingEditedIndex else {
            print("Trying to submit row updates while rowBeingEditedIndex is nil")
            return
        }
        
        let isNewRecord = isNewRecordRow(rowBeingEditedIndex)
        
        // Iterate through the row cells and collect all the values from the textfield
        var cells: [Cell] = []
        for columnIndex in 0..<self.tableView.numberOfColumns {
            let cellView = (self.tableView.view(atColumn: columnIndex, row: rowBeingEditedIndex, makeIfNecessary: false)! as? DatabaseTableViewCell)!
            
            // Extract value from text field
            let stringValue: String? = cellView.textField!.stringValue
            var representationValue: CellValueRepresentation
            if stringValue!.isEmpty || stringValue == CellValueRepresentation.nullString { // TODO: this will prevent someone from setting a value NULL to a string
                representationValue = .null
            } else {
                representationValue = .actual(stringValue!)
            }
            
            // Compare extracted value from text field to the current cell value
            guard cellView.content!.value != representationValue else { continue }
            
            // Skips unparseable or unsupported types
            guard cellView.content!.value != .unparseable, cellView.content!.value != .unsupported else { continue }
            
            let newCell = Cell(column: self.data.columns[columnIndex], value: representationValue, position: columnIndex, isDirty: true)
                        
            if isNewRecord {
                // For new record, all cells are relevant
                cells.append(newCell)
            } else {
                // For an update, only include cell values that were modified
                if newCell.value != self.data.rows[rowBeingEditedIndex].cells[columnIndex].value {
                    cells.append(newCell)
                }
            }                        
        }
        
        let newSelectResultRow: SelectResultRow
        if isNewRecord {
            // If it's a new row, create a dummy UUID
            newSelectResultRow = SelectResultRow(id: UUID().uuidString, cells: cells)
            self.appKitDelegate?.onRowInsert(selectResultRow: newSelectResultRow) { result in
                switch result {
                case .success:
                    print("Row inserted successfully.")                
                    
                    let rowIndexSet = IndexSet(integer: rowBeingEditedIndex)
                    let columnRange = 0..<self.data.columns.count
                    let allColumns = IndexSet(columnRange)

                    self.tableView.reloadData(forRowIndexes: rowIndexSet, columnIndexes: allColumns)
                    
                    self.rowBeingEditedIndex = nil
                    self.isInsertingRow = false
                case .failure(let error):                    
                    if let searchlightAPIError = error as? SearchlightAPIError {
                        
                        // Determine the column index based on the presence of columnName
                        let columnIndex: Int?
                        if let columnName = searchlightAPIError.columnName {
                            columnIndex = self.data.columnIndex(withName: columnName)
                        } else {
                            columnIndex = self.tableView.selectedColumn
                        }
                        
                        if let cell = self.tableView.view(atColumn: columnIndex!, row: rowBeingEditedIndex, makeIfNecessary: false) as? DatabaseTableViewCell {
                            let popover = NSPopover()
                            let viewController = PopoverViewController(with: ColumnErrorView(searchlightAPIError: searchlightAPIError))
                            popover.contentViewController = viewController
                            popover.behavior = .transient
                            popover.show(relativeTo: cell.bounds, of: cell, preferredEdge: .maxY)                        
                        }
                    } else {
                        self.flashRow(rowBeingEditedIndex, color: .red)
                        print("Error inserting row: \(error)")
                    }
               }
            }
        } else {
            // If it's an update, utilize ctid
            newSelectResultRow = SelectResultRow(id: self.data.rows[rowBeingEditedIndex].id, cells: cells)
            self.appKitDelegate?.onRowUpdate(selectResultRow: newSelectResultRow) { result in
                // TODO: implement update callback
            }
        }
    }
        
    func flashRow(_ rowIndex: Int, color: NSColor) {
        let rowView = self.tableView?.rowView(atRow: rowIndex, makeIfNecessary: false)!
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            rowView!.animator().backgroundColor = color
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                rowView!.animator().backgroundColor = color
            }, completionHandler: {
            })
        })
    }
    
    // MARK: - Utility Methods
    
    // Utility method to check if a row is the new record row.
    private func isNewRecordRow(_ row: Int) -> Bool {
        return isInsertingRow && row == data.rows.count
    }
            
    @objc private func copyCellValue() {
        let cellValue = selectedCell!.value.stringRepresentation
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cellValue, forType: .string)
    }
    
    @objc private func deleteRow() {
        guard !readOnly else { return }
        self.appKitDelegate?.onRowDelete(selectResultRow: selectedRow!) { result in
            switch result {
            case .success:
                print("Row deleted successfully.")
            case .failure(let error):
                if let searchlightAPIError = error as? SearchlightAPIError {
                    if let cell = self.tableView.view(atColumn: self.actionCoordinate!.column!, row: self.actionCoordinate!.row, makeIfNecessary: false) as? DatabaseTableViewCell {
                        let popover = NSPopover()
                        let viewController = PopoverViewController(with: ColumnErrorView(searchlightAPIError: searchlightAPIError))
                        popover.contentViewController = viewController
                        popover.behavior = .transient
                        popover.show(relativeTo: cell.bounds, of: cell, preferredEdge: .maxY)
                    }
                } else {
                    self.flashRow(self.actionCoordinate!.row, color: .red)
                    print("Error deleting row: \(error)")
                }
                
            }
        }
    }
    
    @objc private func copyAsSQLInsert() {
//        let cellValues = selectedRow!.cells.map { $0.value }
//        let columnNames = selectedRow!.cells.map { $0.column.name }
//        let pasteboard = NSPasteboard.general
//        pasteboard.clearContents()
    }
    
    @objc private func duplicateRow() {
        isInsertingRow = true
        rowBeingEditedIndex = data.rows.count
        tableView.insertRows(at: IndexSet(integer: data.rows.count), withAnimation: .slideDown)
    }
}

extension TableViewAppKit: DatabaseTableViewRowDelegate {
    
    func didPressTab(cell: Cell) {
        handleTabOrBacktab(cell: cell, isTab: true)
    }
    
    func didPressBacktab(cell: Cell) {
        handleTabOrBacktab(cell: cell, isTab: false)
    }
    
    func didPressEnter() {
        submitEditing()
    }
    
    func didCancelEditing(cell: Cell) {
        cancelEditing()
    }
    
    private func handleTabOrBacktab(cell: Cell, isTab: Bool) {
        guard let rowBeingEditedIndex = rowBeingEditedIndex else {
            print("Row being edited is nil even though backtab got called")
            return
        }
        
        let columnIndex = data.columns.firstIndex(of: cell.column)
        
        // Flags to determine whether we should just stop editing
        let isTabAndLastCell = isTab && columnIndex == data.columns.count - 1
        let isBackTabAndFirstCell = !isTab && columnIndex == 0
        
        if isTabAndLastCell || isBackTabAndFirstCell {
            // Is first cell, just stop editing            
            cancelEditing()
        } else {
            let desiredSelectedIndex = isTab ? columnIndex! + 1 : columnIndex! - 1
            if let previousCell = self.tableView.view(atColumn: desiredSelectedIndex, row: rowBeingEditedIndex, makeIfNecessary: false) as? DatabaseTableViewCell {
                previousCell.textField?.becomeFirstResponder()
                self.tableView.scrollColumnToVisible(desiredSelectedIndex)
            }
        }
    }
}

// MARK: - AppKit Integration
// The section below is responsible for connecting this AppKit class with SwiftUI.
// There's a fair share of boiler plate code that needs to be added, and easy to forget or get confused, so I'm fairly verbose with the comments.

// The NSViewRepresentable is the class that will expose an interface to AppKit
struct DataTable: NSViewRepresentable {

    // References to blocks that are passed from SwiftUI so they can be called from the Coordinator
    internal var onRowUpdateCallback: ((SelectResultRow, @escaping (Result<Void, any Error>) -> Void) -> Void)?
    internal var onRowInsertCallback: ((SelectResultRow, @escaping (Result<Void, any Error>) -> Void) -> Void)?
    internal var onRowDeleteCallback: ((SelectResultRow, @escaping (Result<Void, any Error>) -> Void) -> Void)?
    internal var onRowDoubleClickCallback: ((SelectResultRow) -> Void)?
    
    @State var data: SelectResult = SelectResult(columns: [], rows: [])
    @ObservedObject var controller: DataTableController
    
    @Binding var sortOrder: [TableDataSortComparator]
    @State var readOnly = true
    @EnvironmentObject var pgApi: PostgresDatabaseAPI
    
    func makeNSView(context: Context) -> TableViewAppKit {
        
        var topLevelObjects: NSArray?
        
        guard Bundle.main.loadNibNamed("TableViewAppKit", owner: self, topLevelObjects: &topLevelObjects) else {
            fatalError("Could not load nib")
        }
        
        let view = topLevelObjects!.first(where: { $0 is TableViewAppKit }) as! TableViewAppKit
        view.autoresizingMask = [.width, .height]
        view.tableView.delegate = view
        view.tableView.dataSource = view
        view.readOnly = readOnly
        controller.dataTable = view
        
        view.appKitDelegate = context.coordinator
        view.commonInit()
        
        return view
    }
    
    func updateNSView(_ nsView: TableViewAppKit, context: Context) {
        // This gets called whenever SwiftUI things that this component needs to be re-rendered.
        guard nsView.data.id != data.id else {
            return
        }
        
        nsView.data = data
        nsView.pgApi = pgApi        
        nsView.sortOrder = sortOrder
        nsView.refreshColumns()
        nsView.tableView.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(representable: self)
    }
    
    // MARK: Methods Exposed to SwiftUI
    // The method below are follows SwiftUI convention of methods that return itself so they
    // can be chained
    
    func onRowUpdate(perform action: @escaping @MainActor (SelectResultRow, @escaping (Result<Void, Error>) -> Void) -> Void) -> Self {
        var dataTable = self
        dataTable.onRowUpdateCallback = action
        return dataTable
    }
  
    func onRowInsert(perform action: @escaping @MainActor (SelectResultRow, @escaping (Result<Void, Error>) -> Void) -> Void) -> Self {
        var dataTable = self
        dataTable.onRowInsertCallback = action
        return dataTable
    }
    
    func onRowDelete(perform action: @escaping @MainActor (SelectResultRow, @escaping (Result<Void, Error>) -> Void) -> Void) -> Self {
        var dataTable = self
        dataTable.onRowDeleteCallback = action
        return dataTable
    }
    
    func onRowDoubleClick(perform action: @escaping @MainActor (SelectResultRow) -> Void) -> Self {
        var dataTable = self
        dataTable.onRowDoubleClickCallback = action
        return dataTable
    }
}

// Protocol for object that will receive actions from TableViewAppKit
protocol TableViewAppKitDelegate: AnyObject {
    func onRowInsert(selectResultRow: SelectResultRow, action: @escaping ((Result<Void, any Error>) -> Void))
    func onRowUpdate(selectResultRow: SelectResultRow, action: @escaping ((Result<Void, any Error>) -> Void))
    func onSort(sortDescriptor: [TableDataSortComparator])
    func onRowDelete(selectResultRow: SelectResultRow, action: @escaping ((Result<Void, any Error>) -> Void))
    func onDoubleClickRow(selectResultRow: SelectResultRow)
}

// The coordinator maps actions from AppKit table view to SwiftUI.
// Code within the NSTableView will call those methods, and the representable is the SwiftUI instance that will handle those methods
class Coordinator: NSObject, TableViewAppKitDelegate {
    var representable: DataTable

    init(representable: DataTable) {
        self.representable = representable
    }
    
    func onRowUpdate(selectResultRow: SelectResultRow, action: @escaping ((Result<Void, any Error>) -> Void)) {
        representable.onRowUpdateCallback?(selectResultRow, action)
    }
    
    func onRowInsert(selectResultRow: SelectResultRow, action: @escaping ((Result<Void, any Error>) -> Void)) {
        representable.onRowInsertCallback?(selectResultRow, action)
    }
    
    func onSort(sortDescriptor: [TableDataSortComparator]) {
        representable.sortOrder = sortDescriptor
    }
    
    func onRowDelete(selectResultRow: SelectResultRow, action: @escaping ((Result<Void, any Error>) -> Void)) {
        representable.onRowDeleteCallback?(selectResultRow, action)
    }
    
    func onDoubleClickRow(selectResultRow: SelectResultRow) {
        representable.onRowDoubleClickCallback?(selectResultRow)
    }
}

// The controller maps actions from SwiftUI to AppKit view AppKit.
// SwiftUI will hold an instance of this controller and call methods based on actions taken on SwiftUI, and will pass it to AppKit layer
class DataTableController: ObservableObject {
    weak var dataTable: TableViewAppKit?
    func insertRow() {
        dataTable?.prepareInsertRow()
    }
}

extension TableViewAppKit: NSTableViewDelegate, NSTableViewDataSource {
    
    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(DatabaseTableViewCell.CellIdentifier), owner: self) as? DatabaseTableViewCell
        
        
        return 300
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        guard let column = data.columns.first(where: { $0.name == tableColumn?.identifier.rawValue }) else {
            fatalError("Column not found. This should not happen")
        }
        
        let cellIdentifier = NSUserInterfaceItemIdentifier(DatabaseTableViewCell.CellIdentifier)
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? DatabaseTableViewCell
        if cell == nil {
            cell = DatabaseTableViewCell.loadFromNib()
            cell?.pgApi = pgApi
        }
                
        // Mark the row as editable if current row is being edited
        if row == rowBeingEditedIndex {
            cell!.isEditing = true
        }
        
        // Render the new row cell
        if isNewRecordRow(row) {
            cell?.setContent(content: Cell(column: column, value: .actual(""), position: column.position), editable: true)
            
            if selectedRow != nil {
                let cellContent = selectedRow!.cells[column.position]
                cell?.setContent(content: cellContent, editable: true)
            }
            
        } else {
            let columnName = tableColumn!.identifier.rawValue
            let cellContent = data.rows[row][columnName]
            cell?.setContent(content: cellContent)
        }
        
        cell?.delegate = self
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return true
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        let selectedIndex = tableView.selectedRowIndexes
        
        // Check if selected indexes are empty
        if selectedIndex.count == 0 {
            submitEditing()
            return
        }
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
