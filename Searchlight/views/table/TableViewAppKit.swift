//
//  TableViewAppKit.swift
//  Searchlight
//
//  Created by Ravel Antunes on 9/14/2025.
//
//  Copyright (c) 2025 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import AppKit

// This file has the core implementation of how to handle data from a database table. It handles the connection between SwiftUI and AppKit.
// Naming of classes and components are messy: I struggled to find names that represent table where that is already overused as components of SwiftUI, AppKit, etc.
class TableViewAppKit: NSView {
    
    @IBOutlet weak var tableView: NSTableView!
    weak var appKitDelegate: TableViewAppKitDelegate?
    
    var data: SelectResult = SelectResult(columns: [], rows: [])
    var sortOrder: [TableDataSortComparator] = []
    var readOnly = true
    
    let tableViewHeader = TableHeaderView()
    var errorPopover: NSView?
    var pgApi: PostgresDatabaseAPI?
    
    internal var currentEditMode: EditingMode = .none
    internal var currentSelection: Coordinate?
    
    // Animation related
    private var previousOffset: CGFloat = 0.0 // Used to detect if user scrolling up or down, so we know when to animate
    private var shouldAnimateCells = true
    private var maxAnimatedIndex = 0 // Keep index to prevent re-animating cell already loaded
    
    // I don't remember why I moved some of this initialization here. It seems to be only used in one place at the moment
    func commonInit() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.action = #selector(tableViewSingleClick(_:))
        tableView.doubleAction = #selector(tableViewDoubleClick(_:))
        tableView.headerView = tableViewHeader
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnResizing = true
        
        if let scrollView = tableView.enclosingScrollView {
           scrollView.contentView.postsBoundsChangedNotifications = true
           NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
       }
    }
    
    func getRow(coordinate: Coordinate?) -> SelectResultRow? {
        guard let coordinate = coordinate,
              coordinate.row < data.rows.count else {
            return nil
        }
        return data.rows[coordinate.row]
    }
    
    func getCell(coordinate: Coordinate?) -> Cell? {
        guard let row = getRow(coordinate: coordinate),
              let column = coordinate!.column,
              column < row.cells.count else {
            return nil
        }
        return row.cells[column]
    }
    
    func transitionTo(to: EditingMode) {
        
        guard currentEditMode != to else {
            return
        }
        
        // if readOnly is true, ignore any transition to update or insert
        if readOnly, to != .none {
            return
        }
        
        // We need to update the current value here so any side effect or other methods called inside the switch can use the updated state
        // However, we cache since sometimes we might need to use the former edit mode
        let cachedCurrentEditMode = currentEditMode
        currentEditMode = to
        print("Transitioning from \(cachedCurrentEditMode) to \(to)")
        
        switch (cachedCurrentEditMode, to) {
        case (.inserting, .none):
            if self.data.rows.count < self.tableView.numberOfRows {
                // If data < rows displayed, means we cancelled insert without a save
                tableView.removeRows(at: IndexSet(integer: data.rows.count))
            } else {
                tableView.reloadData(forRowIndexes: IndexSet(integer: data.rows.count-1), columnIndexes: IndexSet(0..<self.tableView.numberOfColumns))
                self.flashRow(data.rows.count-1, color: .green)
            }
            tableView.window?.endEditing(for: nil)
            currentSelection = nil
            break
        case (.updating(let coordinate), .none):
            tableView.window?.makeFirstResponder(nil)
            tableView.reloadData(forRowIndexes: IndexSet(integer: coordinate.row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
            currentSelection = nil
            break
        case (.none, .inserting):
            let newRowIndexSet = IndexSet(integer: data.rows.count)
            self.tableView.insertRows(at: newRowIndexSet, withAnimation: .effectGap)
            self.tableView.selectRowIndexes(newRowIndexSet, byExtendingSelection: false)
            self.tableView.scrollRowToVisible(newRowIndexSet.first!)
            self.currentSelection = Coordinate(row: data.rows.count, column: 0)
            break
        case (.none, .updating(let coordinate)):
            // Update rows at indexpath
            tableView.reloadData(forRowIndexes: IndexSet(integer: coordinate.row), columnIndexes: IndexSet(integer: coordinate.column!))
            break
        default:
            break
        }
    }
    
    @objc func tableViewSingleClick(_ sender: AnyObject) {
        currentSelection = Coordinate(row: tableView.clickedRow, column: tableView.clickedColumn)
        transitionTo(to: .none)
    }
    
    @objc func tableViewDoubleClick(_ sender: AnyObject) {
        currentSelection = Coordinate(row: tableView.clickedRow, column: tableView.clickedColumn)
        if currentSelection!.hasValidRow {
            transitionTo(to: .updating(coordinate: currentSelection!))
        } else {
            transitionTo(to: .inserting)
        }
        
        // This is used on instances where we can show DataTable embedded in popover and want to callback a selection
        if let appKitDelegate = appKitDelegate, let row = getRow(coordinate: currentSelection) {
            appKitDelegate.onDoubleClickRow(selectResultRow: row)
        }
    }
    
    func didUpdateData() {
        previousOffset = 0.0
        shouldAnimateCells = true
        maxAnimatedIndex = Int(tableView.frame.height / 17.0) // TODO: not keep it a constant here
        
        refreshColumns()
        tableView.reloadData()
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

            tableViewHeader.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                tableViewHeader.animator().alphaValue = 1
            }
            self.tableView.addTableColumn(tableColumn)
        }
        
        if let sortOrder = self.sortOrder.first {
            let sortDescriptor = NSSortDescriptor(key: sortOrder.columnKey, ascending: sortOrder.order == .forward ? true : false)
            self.tableView.sortDescriptors = [sortDescriptor]
        }
        
        // TODO: adding this here for convenience, but makes more sense to live somwhere, perhaps encapsulate all "refresh" of the view in a single method
        tableViewHeader.data = data
    }
    
    override func rightMouseDown(with event: NSEvent) {
        guard !readOnly else { return }
        
        let globalLocation = event.locationInWindow
        let localLocation = tableView.convert(globalLocation, from: nil)
        let clickedRowIndex = tableView.row(at: localLocation)
        let clickedCellIndex = tableView.column(at: localLocation)
        currentSelection = Coordinate(row: clickedRowIndex, column: clickedCellIndex)
        
        let isClickingOnARow = clickedRowIndex != -1
//        selectedRow = data.rows.indices.contains(clickedRowIndex) ? data.rows[clickedRowIndex] : nil
        
        let isMultipleRowsSelected = tableView.selectedRowIndexes.count > 1
        let menu = NSMenu(title: "Context Menu")
        menu.autoenablesItems = false
        
        let selector = #selector(copyValue)
        let addFormatOptionsToCopyMenu: (NSMenuItem) -> Void = { menuItem in
            menuItem.submenu = NSMenu()
            menuItem.submenu?.addItem(withTitle: "as CSV", action: selector, keyEquivalent: "")
            menuItem.submenu?.addItem(withTitle: "as SQL", action: selector, keyEquivalent: "")
            // TODO: implement JSON
            //menuItem.submenu?.addItem(withTitle: "as JSON", action: selector, keyEquivalent: "")
        }

        let copyValueMenuItem = menu.addItem(withTitle: "Copy Cell", action: selector, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        let copyRowMenuItem = menu.addItem(withTitle: "Copy Row Values", action: nil, keyEquivalent: "")
        addFormatOptionsToCopyMenu(copyRowMenuItem)
        
        if isMultipleRowsSelected {
            let copyColumnValues = menu.addItem(withTitle: "Copy Column Values", action: selector, keyEquivalent: "")
            let copyAllValues = menu.addItem(withTitle: "Copy All Values", action: selector, keyEquivalent: "")
            [copyColumnValues, copyAllValues].forEach { addFormatOptionsToCopyMenu($0) }
        }
        
        // option to add a selected value as filter (ie.: column = value of the selected cell)
        //let addToFilter = menu.addItem(withTitle: "Add to Filter", action: <#T##Selector?#>, keyEquivalent: <#T##String#>)
  
        menu.addItem(NSMenuItem.separator())
//        _ = menu.addItem(withTitle: "Insert Row", action: #selector(prepareInsertRow), keyEquivalent: "")
        let duplicateRowMenuItem = menu.addItem(withTitle: "Duplicate Row", action: #selector(duplicateRow), keyEquivalent: "")
        duplicateRowMenuItem.isEnabled = false
        
        let shouldAddSToDeleteRow = isMultipleRowsSelected ? "s" : ""
        let deleteRowMenuItem = menu.addItem(withTitle: "Delete Row\(shouldAddSToDeleteRow)", action: #selector(deleteRow), keyEquivalent: "")
        
        // Disable items that are only relevant in the context of a selected row
        if !isClickingOnARow {
            copyValueMenuItem.isEnabled = false
            duplicateRowMenuItem.isEnabled = false
            deleteRowMenuItem.isEnabled = false
        }

        NSMenu.popUpContextMenu(menu, with: event, for: tableView)
    }

    
    func submitEditing() {
        
        // Guard against currectSelection being set, and being in editing or inserting mode
        guard let currentSelection, currentEditMode != .none else {
            fatalError("submitEditing called but currentSelection or currentEditMode is not set. \(currentSelection.debugDescription), \(currentEditMode)")
        }
        
        // Iterate through the row cells and collect all the values from the textfield
        var cells: [Cell] = []
        for columnIndex in 0..<self.tableView.numberOfColumns {
            let cellView = (self.tableView.view(atColumn: columnIndex, row: currentSelection.row, makeIfNecessary: false)! as? DatabaseTableViewCell)!

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
                        
            if currentEditMode == .inserting {
                // For new record, all cells are relevant
                cells.append(newCell)
            } else {
                // For an update, only include cell values that were modified
                if newCell.value != self.data.rows[currentSelection.row].cells[columnIndex].value {
                    cells.append(newCell)
                }
            }
        }
        
        let newSelectResultRow: SelectResultRow
        if currentEditMode == .inserting {
            // If it's a new row, create a dummy UUID
            newSelectResultRow = SelectResultRow(id: UUID().uuidString, cells: cells)
            self.appKitDelegate?.onRowInsert(selectResultRow: newSelectResultRow) { result in
                switch result {
                case .success:
                    
                    let newRow = try! result.get()
                    var currentRows = self.data.rows
                    currentRows.append(newRow)
                    
                    let updatedData = SelectResult(
                        id: self.data.id,
                        columns: self.data.columns,
                        rows: currentRows,
                        tableName: self.data.tableName
                    )
                    self.data = updatedData
                    self.transitionTo(to: .none)
                    
                case .failure(let error):
                    if let searchlightAPIError = error as? SearchlightAPIError {
                        
                        // Determine the column index based on the presence of columnName
                        let columnIndex: Int?
                        if let columnName = searchlightAPIError.columnName {
                            columnIndex = self.data.columnIndex(withName: columnName)
                        } else {
                            columnIndex = self.tableView.selectedColumn
                        }
                        
                        if let cell = self.tableView.view(atColumn: columnIndex!, row: currentSelection.row, makeIfNecessary: false) as? DatabaseTableViewCell {
                            let popover = NSPopover()
                            let viewController = PopoverViewController(with: ColumnErrorView(searchlightAPIError: searchlightAPIError))
                            popover.contentViewController = viewController
                            popover.behavior = .transient
                            popover.show(relativeTo: cell.bounds, of: cell, preferredEdge: .maxY)
                        }
                    } else {
                        self.flashRow(currentSelection.row, color: .red)
                        print("Error inserting row: \(error)")
                    }
                }
            }
        } else {
            // If it's an update, utilize existing ctid
            let currentRowData = getRow(coordinate: currentSelection)!
            newSelectResultRow = SelectResultRow(id: currentRowData.id, cells: cells) // This will only contain the cells that were updated
            self.appKitDelegate?.onRowUpdate(selectResultRow: newSelectResultRow) { result in
                switch result {
                case .success:
                    
                    // Make a copy of rows, replacing the matching row
                    var updatedRows = self.data.rows
                    var currentCells = currentRowData.cells
                    
                    // Update the cells that were changed into the currentCells
                    for updatedCell in cells {
                        currentCells[updatedCell.position] = updatedCell
                    }
                    updatedRows[currentSelection.row] = SelectResultRow(id: currentRowData.id, cells: currentCells)

                    // Create a new SelectResult with the updated rows
                    let updatedData = SelectResult(
                        id: self.data.id,
                        columns: self.data.columns,
                        rows: updatedRows,
                        tableName: self.data.tableName
                    )

                    // Replace self.data with the new value
                    self.data = updatedData
                    self.tableView.reloadData(forRowIndexes: IndexSet(integer: currentSelection.row), columnIndexes: IndexSet(integersIn: 0..<self.tableView.numberOfColumns))
                    self.transitionTo(to: .none)
                    self.flashRow(currentSelection.row, color: .green)
                    break
                case .failure(let error):
                    self.flashRow(currentSelection.row, color: .red)
                    print("Error updating row: \(error)")
                    break
                }
            }
        }
    }
    
    // MARK: - Utility Methods
    // This function is used to detect scroll, and by using previousOffset property we can determine if user is scrolling up or down
    // This imformation is useful for some transition animations
    @objc func boundsDidChange(notification: Notification) {
        guard let contentView = notification.object as? NSClipView else { return }
        
        let currentOffset = contentView.bounds.origin.y
        shouldAnimateCells = currentOffset > previousOffset
        previousOffset = currentOffset
    }
    
    @objc private func deleteRow() {
        guard !readOnly else { return }
        
        let isMultipleRowsSelected = tableView.selectedRowIndexes.count > 1
        var coordinates: [Coordinate]
        
        if isMultipleRowsSelected {
            coordinates = tableView.selectedRowIndexes.map { .init(row: $0, column: nil) }
        } else {
            coordinates = [currentSelection!]
        }
        let rows = coordinates.map { getRow(coordinate: $0)! }

        self.appKitDelegate?.onRowDelete(selectResultRow: rows) { result in
            switch result {
            case .success:
                let removedRows =  IndexSet(coordinates.map(\.row))
                
                // Remove row from data object
                var currentRows = self.data.rows
                currentRows.remove(atOffsets: removedRows)
                
                let updatedData = SelectResult(
                    id: self.data.id,
                    columns: self.data.columns,
                    rows: currentRows,
                    tableName: self.data.tableName
                )
                self.data = updatedData                
                
                self.tableView.removeRows(at: removedRows, withAnimation: .slideUp)                
            case .failure(let error):
                if let searchlightAPIError = error as? SearchlightAPIError {
                    if let cell = self.tableView.view(atColumn: self.currentSelection!.column!, row: self.currentSelection!.row, makeIfNecessary: false) as? DatabaseTableViewCell {
                        let popover = NSPopover()
                        let viewController = PopoverViewController(with: ColumnErrorView(searchlightAPIError: searchlightAPIError))
                        popover.contentViewController = viewController
                        popover.behavior = .transient
                        popover.show(relativeTo: cell.bounds, of: cell, preferredEdge: .maxY)
                    }
                } else {
                    self.flashRow(self.currentSelection!.row, color: .red)
                    print("Error deleting row: \(error)")
                }
                
            }
        }
    }
    
    @objc private func copyValue(_ sender: NSMenuItem) {

        let copiedData: [[CellValueRepresentation]]
        var columnNames: [String] = []
        if sender.parent == nil {
            print("copying cell values")
            copiedData = [[data.rows[currentSelection!.row].cells[currentSelection!.column!].value]]
        } else if sender.parent!.title.lowercased().contains("row") {
            print("copying row values")
            copiedData = [data.rows[currentSelection!.row].cells.map{$0.value}]
            columnNames = data.columns.map{$0.name}
        } else if sender.parent!.title.lowercased().contains("column") {
            print("copying column values")
            copiedData = data.rows.map{[$0.cells[currentSelection!.column!].value]}
            columnNames = [data.columns[currentSelection!.column!].name]
        } else {
            print("copying all")
            copiedData = data.rows.map{$0.cells.map{$0.value}}
            columnNames = data.columns.map{$0.name}
        }
        
        let stringValue =
        {
            if sender.title.lowercased().contains("csv") {
                print("as csv")
                return copiedData.map{$0.map{cell in cell.stringRepresentation}.joined(separator: "\t")}.joined(separator: "\n")
            } else if sender.title.lowercased().contains("json") {
                print("as json")
                
                return ""
            } else if sender.title.lowercased().contains("sql") {
                // TODO: validate how this works on editor (no tableName)
                return generateInsertStatement(tableName: data.tableName!, columns: columnNames, rows: copiedData)
            }
            return copiedData.first!.first!.stringRepresentation
        }()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(stringValue, forType: .string)
    }
    
    // TODO: move this somewhere else
    private func generateInsertStatement(tableName: String, columns: [String], rows: [[CellValueRepresentation]]) -> String {
        guard !rows.isEmpty else { return "" }
        
        // Build the list of columns (e.g., "col1, col2, col3")
        let columnsPart = columns.joined(separator: ", ")
        
        let values = rows.map { row in
            let joinedCellValues = row.map{$0.sqlValueString}.joined(separator: ", ")
            return "(" + joinedCellValues + ")"
            
        }.joined(separator: ",\n")
        
        // Combine schema and table name in the INSERT statement
        return "INSERT INTO \"\(tableName)\" (\(columnsPart)) VALUES\n\(values);"
    }
    
    @objc private func duplicateRow() {
//        isInsertingRow = true
//        rowBeingEditedIndex = data.rows.count
        tableView.insertRows(at: IndexSet(integer: data.rows.count), withAnimation: .slideDown)
    }
}
