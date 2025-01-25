//
//  DatabaseViewer.swift
//  Searchlight
//
//  Created by Ravel Antunes on 6/12/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation
import SwiftUI

struct DatabaseViewer: View {
    
    @EnvironmentObject var appState: AppState    
    @EnvironmentObject var pgApi: PostgresDatabaseAPI

    @StateObject var dataTableController = DataTableController()

    @State private var queryParams = QueryParameters()
    @State private var sortOrder: [TableDataSortComparator] = []
    @State private var data: SelectResult = SelectResult(columns: [], rows: [])
    @State private var errorMessage: String = ""
    @State private var eventMonitor: Any?
    
    @State private var showEditor = false
    @State private var text = ""
    @State private var isLoading = false
    
    // Keep reference to current API call task, so it can be cancelled
    @State private var currentTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if showEditor {
                AppKitTextView(text: $text, onQuerySubmit: { queryString in
                    Task {
                        do {
                            withAnimation {
                                isLoading = true
                            }
                            defer {
                                withAnimation {
                                    isLoading = false
                                }
                            }
                            do {
                                errorMessage = ""
                                data = try await pgApi.execute(queryString)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                            
                            // TODO: implement error handling from editor
                        }
                    }
                })
            } else {
                TableFilter(columns: data.columns, queryParams: $queryParams)
            }
            ZStack {
                DataTable(data: data, controller: dataTableController, sortOrder: $sortOrder, readOnly: false)
                    .onRowUpdate(perform: handleRowUpdate)
                    .onRowInsert(perform: handleRowInsert)
                    .onRowDelete(perform: handleRowDelete)
                    .disabled(isLoading)
                    .id(data.id)
                
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: isLoading)
            HStack(alignment: .center) {
                Button(action: {
                    dataTableController.insertRow()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12)) // Adjusts the size of the symbol
                }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Add")
                    .padding(3)
                    .disabled(data.tableName == nil)
                Text(errorMessage)
                Spacer()
            }
        }
        .toolbar(content: {
            ToolbarItem(placement: ToolbarItemPlacement.cancellationAction) {
                Button {
                    showEditor.toggle()
                } label: {
                    Label("Editor", systemImage: "terminal.fill")
                        .foregroundColor(showEditor ? .blue : .primary)
                    }
                }
            })
            .onChange(of: sortOrder) { oldValue, newValue in
                self.queryParams = QueryParameters(schemaName: self.queryParams.schemaName, tableName: self.queryParams.tableName, sortColumn: newValue.first?.columnKey, sortOrder: newValue.first?.order, limit: self.queryParams.limit, filters: self.queryParams.filters)
                self.refreshData()
            }
            .frame(maxHeight: .infinity, alignment: .top)      
            .onChange(of: appState.selectedTable, initial: true) { oldValue, newValue in
                guard let table = newValue, newValue != oldValue else {
                    return
                }
                errorMessage = ""
                $showEditor.wrappedValue = false
                sortOrder = []
                queryParams = QueryParameters(schemaName: table.schema, tableName: table.name, sortColumn: nil, sortOrder: nil, limit: 100, filters: [])
            }
            .onChange(of: queryParams) {oldValue, newValue in
                refreshData()
            }
            .environmentObject(pgApi)
            .onAppear {
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.modifierFlags.contains(.command) && event.keyCode == 15 {
                        refreshData()
                        return nil
                    }
                    return event
                }
            }
            .onDisappear {
                // Remove the event monitor when the view disappears
                if let monitor = eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    eventMonitor = nil
                }
            }
    }
    
    func handleRowUpdate(selectResultRow: SelectResultRow, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await pgApi.updateRow(schemaName: self.appState.selectedTable!.schema, tableName: appState.selectedTable!.name, row: selectResultRow)
                completion(.success(()))
                refreshData()
            } catch {
                completion(.failure(error))
                print(error.localizedDescription)
                self.errorMessage = "Error updating row: \(error)"
            }
        }
    }

    func handleRowInsert(selectResultRow: SelectResultRow, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                _ = try await pgApi.insertRow(schemaName: self.appState.selectedTable!.schema, tableName: appState.selectedTable!.name, row: selectResultRow)
                completion(.success(()))
                refreshData()
            } catch {
                completion(.failure(error))
                self.errorMessage = "Error on insert: \(error)"
            }
        }
    }
    
    func handleRowDelete(selectResultRow: SelectResultRow, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await pgApi.deleteRow(schemaName: self.appState.selectedTable!.schema, tableName: self.appState.selectedTable!.name, row: selectResultRow)
                completion(.success(()))
                refreshData()
            } catch {
                completion(.failure(error))
                self.errorMessage = "Error on delete: \(error)"
            }
        }
    }
    
    private func refreshData() {
        currentTask?.cancel()
        currentTask = Task {
            errorMessage = ""
            withAnimation {
                isLoading = true
            }
            defer {
                withAnimation {
                    isLoading = false
                }
            }
                        
            do {
                let data = try await pgApi.select(params: queryParams)
                guard !Task.isCancelled else { return }
                self.data = data
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
