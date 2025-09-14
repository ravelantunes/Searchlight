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
import SwiftUI

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
    internal var onRowInsertCallback: ((SelectResultRow, @escaping (Result<SelectResultRow, any Error>) -> Void) -> Void)?
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
        // This gets called whenever SwiftUI thinks this component needs to be re-rendered.
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
  
    func onRowInsert(perform action: @escaping @MainActor (SelectResultRow, @escaping (Result<SelectResultRow, Error>) -> Void) -> Void) -> Self {
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
    func onRowInsert(selectResultRow: SelectResultRow, action: @escaping ((Result<SelectResultRow, any Error>) -> Void))
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
    
    func onRowInsert(selectResultRow: SelectResultRow, action: @escaping ((Result<SelectResultRow, any Error>) -> Void)) {
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
