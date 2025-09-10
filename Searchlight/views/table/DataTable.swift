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

enum EditingMode: Equatable {
    case none
    case inserting
    case updating(coordinate: Coordinate)
}


// Represents something similar to an indexPath, so it can keep reference to specific points in the table
struct Coordinate: Equatable {
    let row: Int
    let column: Int?
    
    var hasValidRow: Bool {
        row >= 0
    }
}

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
    
    private var mode: EditingMode = .none
                
    // Animation related
    private var previousOffset: CGFloat = 0.0 // Used to detect if user scrolling up or down, so we know when to animate
    private var shouldAnimateCells = true
    private var maxAnimatedIndex = 0 // Keep index to prevent re-animating cell already loaded
        
    private var currentEditMode: EditingMode = .none
    private var currentSelection: Coordinate?
    
    // I don't remember why I moved some of this initialization here
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
        
        switch (cachedCurrentEditMode, to) {
        case (.inserting, .none):
            tableView.removeRows(at: IndexSet(integer: data.rows.count))
            currentSelection = nil
            break
        case (.updating(let coordinate), .none):
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
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return data.rows.count + (currentEditMode == .inserting ? 1 : 0)
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
        
        let isMultipleRowsSelected = tableView.selectedRowIndexes.count > 0
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
        let deleteRowMenuItem = menu.addItem(withTitle: "Delete Row", action: #selector(deleteRow), keyEquivalent: "")
        
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
            print("Value \(representationValue)")
            
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
                    print("Row inserted successfully.")                                    
                    let rowIndexSet = IndexSet(integer: currentSelection.row)
                    let allColumns = IndexSet(0..<self.data.columns.count)
                    self.tableView.reloadData(forRowIndexes: rowIndexSet, columnIndexes: allColumns)
                    self.transitionTo(to: .none)
                    self.flashRow(currentSelection.row, color: .green)
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


    /// Subtle, non-intrusive visual feedback for a successfully updated row.
    /// If the row is visible, it overlays a tinted view that quickly fades out.
    ///
    /// - Parameters:
    ///   - row: Row index to flash.
    ///   - color: Base tint color (alpha is applied below).
    ///   - alpha: Max alpha for the overlay at the peak of the animation.
    ///   - fadeIn: Duration of the quick fade-in.
    ///   - hold: Time to keep the overlay before fading out.
    ///   - fadeOut: Duration of the fade-out.
    ///   - cornerRadius: Corner radius for the overlay.
    ///   - inset: Inset inside the row bounds so it doesn’t butt up against edges.
    ///   TODO: move to an extension
    func flashRow(_ row: Int,
                  color: NSColor = .controlAccentColor,
                  alpha: CGFloat = 0.25,
                  fadeIn: TimeInterval = 0.08,
                  hold: TimeInterval = 0.20,
                  fadeOut: TimeInterval = 0.45,
                  cornerRadius: CGFloat = 6,
                  inset: CGFloat = 2) {
        guard row >= 0, row < tableView.numberOfRows else { return }

        // Only animate if the row view is currently realized/visible.
        guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) else { return }

        // Create a lightweight overlay that tracks the row's size.
        let overlay = NSView(frame: rowView.bounds.insetBy(dx: inset, dy: inset))
        overlay.wantsLayer = true
        overlay.translatesAutoresizingMaskIntoConstraints = false

        if overlay.layer == nil {
            overlay.wantsLayer = true
        }
        overlay.layer?.backgroundColor = color.withAlphaComponent(alpha).cgColor
        overlay.layer?.cornerRadius = cornerRadius
        overlay.alphaValue = 0

        rowView.addSubview(overlay)

        // Pin overlay to rowView with insets so it resizes with layout changes.
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: inset),
            overlay.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -inset),
            overlay.topAnchor.constraint(equalTo: rowView.topAnchor, constant: inset),
            overlay.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -inset),
        ])

        // Animate: quick fade-in, brief hold, smooth fade-out, then remove.
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fadeIn
                overlay.animator().alphaValue = 1.0
            } completionHandler: {
                DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = fadeOut
                        overlay.animator().alphaValue = 0.0
                    } completionHandler: {
                        overlay.removeFromSuperview()
                    }
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
        let row = getRow(coordinate: currentSelection!)!
        self.appKitDelegate?.onRowDelete(selectResultRow: row) { result in
            switch result {
            case .success:
                self.tableView.removeRows(at: IndexSet(integer: self.currentSelection!.row), withAnimation: .slideUp)
                print("Row deleted successfully.")
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

// Implements delegate that will receive callbacks from Row events
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
        transitionTo(to: .none)
    }
    
    private func handleTabOrBacktab(cell: Cell, isTab: Bool) {
        // Flags to determine whether we should just stop editing
        let isTabAndLastCell = isTab && currentSelection!.column! == data.columns.count - 1
        let isBackTabAndFirstCell = !isTab && currentSelection!.column! == 0
        
        if isTabAndLastCell || isBackTabAndFirstCell {
            // Is first cell, just stop editing
            transitionTo(to: .none)
        } else {
            let desiredSelectedIndex = isTab ? currentSelection!.column! + 1 : currentSelection!.column! - 1
            if let cellView = self.tableView.view(atColumn: desiredSelectedIndex, row: currentSelection!.row, makeIfNecessary: false) as? DatabaseTableViewCell {
                currentSelection = Coordinate(row: currentSelection!.row, column: desiredSelectedIndex)
                cellView.isEditing = true
                window?.makeFirstResponder(cellView.textField!)
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
        nsView.didUpdateData()
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

// The controller maps actions from SwiftUI to AppKit view.
// Use this to send actions/events to AppKit when it doesn't make sense to just update a data model.
// SwiftUI will hold an instance of this controller and call methods based on actions taken on SwiftUI, and will pass it to AppKit layer
class DataTableController: ObservableObject {
    weak var dataTable: TableViewAppKit?
    func insertRow() {
        dataTable?.transitionTo(to: .inserting)
    }
}

extension TableViewAppKit: NSTableViewDelegate, NSTableViewDataSource {
    
    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
//        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(DatabaseTableViewCell.CellIdentifier), owner: self) as? DatabaseTableViewCell
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
        
//        if isEditable && self.currentSelection!.column == column.position {
//            cellView.textField.becomeFirstResponder()
//        }
                    
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
