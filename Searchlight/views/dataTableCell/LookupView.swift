//
//  LookupView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 12/24/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//
import SwiftUI

class LookUpViewModel: ObservableObject {
    // Columns from the target table used in the search
    @Published var columns: [Column]
    
    // Name of table to look up values from
    @Published var targetTable: String
    
    // Name of schema to look up values from
    @Published var targetSchema: String
    
    init(columns: [Column], targetTable: String, targetSchema: String) {
        self.columns = columns
        self.targetTable = targetTable
        self.targetSchema = targetSchema
    }
}


// View to be used to do a quick lookup in a table specified by targetTable
// Currently used in the popover on a cell that has a relationship to another table.
struct LookupView: View {
    
    @ObservedObject var lookUpViewModel: LookUpViewModel
    
    // Current column being used in search lookup
    @State private var selectedColumn: Column?
    
    // Current value used in search query
    @State private var lookupValue: String = ""
    
    // Results from search query
    @State private var results: [SelectResultRow] = []

    // Callback for when any query params changes and new results needs to be fetched
    @State var onLookupChange: ((Column, String, @escaping (Result<SelectResult, any Error>) -> Void) -> Void)?
    
    // Callback for when user selects a row
    @State var onRowSelection: ((SelectResultRow) -> Void)
    
    // Callback to notify parent view to close this popover
    @State var onClose: (() -> Void)
        
    // Event monitor for keys, so event registration and de-registration state can be managed outside of SwiftUI
    @StateObject private var keyEventMonitor = KeyEventMonitor()
    
    @StateObject var dataTableController = DataTableController()
    
    @EnvironmentObject var pgApi: PostgresDatabaseAPI

    @State private var sortOrder: [TableDataSortComparator] = []
    
    @State private var data: SelectResult = SelectResult(columns: [], rows: [])
    
    @State var isLoading = true

    var body: some View {
        if lookUpViewModel.columns.isEmpty {
            VStack {
               ProgressView("Loading...")
                   .progressViewStyle(CircularProgressViewStyle())
                   .padding()
            }
            .transition(.opacity)
        } else {
            Text("Looking up records in \(lookUpViewModel.targetTable)")
                .font(.subheadline)
                .onAppear {
                    keyEventMonitor.startMonitoring(escapeKey: onClose)
                }
                .onDisappear {
                    keyEventMonitor.stopMonitoring()
                }
                .padding(.top, 5)
            HStack {
                Picker("", selection: $selectedColumn) {
                    ForEach(lookUpViewModel.columns) { column in
                        Text(column.name).tag(column)
                    }
                }
                TextField("", text: $lookupValue)
                    .textFieldStyle(.roundedBorder)
                    .padding(.trailing, 3) // This is a hack to make look better. Not sure why the margins weren't consistent
            }
            .padding(5)
            DataTable(data: data, controller: dataTableController, sortOrder: $sortOrder)
                .onRowDoubleClick { row in
                    onRowSelection(row)
                }
                .id(data.id)
                .environmentObject(pgApi)
                .onChange(of: lookupValue) {
                    triggerLookup()
                }
                .onChange(of: selectedColumn) {
                    results = []
                    lookupValue = ""
                    triggerLookup()
                }
                .onReceive(lookUpViewModel.$columns) { loaded in
                    if lookUpViewModel.columns.count > 0 {
                        selectedColumn = lookUpViewModel.columns.first
                    }
                }
        }
    }
    
    func triggerLookup() {
        Task {
            do {
                
                let params = QueryParameters(schemaName: lookUpViewModel.targetSchema, tableName: lookUpViewModel.targetTable, filters: [
                    lookupValue == "" ? nil : Filter(column: selectedColumn!.name, value: lookupValue, operation: .startsWith)
                ].compactMap { $0 })
                data = try await self.pgApi.select(params: params)
            }
        }
    }
}
