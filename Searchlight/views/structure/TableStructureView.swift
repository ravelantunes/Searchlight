//
//  TableStructureView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/9/26.
//
//  Copyright (c) 2026 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

struct TableStructureView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var pgApi: PostgresDatabaseAPI

    // Whether this view is currently visible/active
    var isActive: Bool = true

    @State private var tableStructure: TableStructure?
    @State private var isLoading = false
    @State private var errorMessage: String = ""
    @State private var selectedTab: StructureTab = .columns
    @State private var hasLoadedInitialData = false

    enum StructureTab: String, CaseIterable {
        case columns = "Columns"
        case indexes = "Indexes"
        case constraints = "Constraints"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(StructureTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(Spacing.sm)

            Divider()

            // Content based on selected tab
            if isLoading {
                Spacer()
                ProgressView("Loading structure...")
                Spacer()
            } else if let structure = tableStructure {
                switch selectedTab {
                case .columns:
                    ColumnsListView(
                        columns: structure.columns,
                        schemaName: structure.schemaName,
                        tableName: structure.tableName,
                        onRefresh: refreshStructure
                    )
                case .indexes:
                    IndexesListView(
                        indexes: structure.indexes,
                        schemaName: structure.schemaName,
                        tableName: structure.tableName,
                        columns: structure.columns,
                        onRefresh: refreshStructure
                    )
                case .constraints:
                    ConstraintsListView(
                        constraints: structure.constraints,
                        schemaName: structure.schemaName,
                        tableName: structure.tableName,
                        columns: structure.columns,
                        onRefresh: refreshStructure
                    )
                }
            } else if !errorMessage.isEmpty {
                Spacer()
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
                Spacer()
            } else {
                Spacer()
                Text("Select a table to view its structure")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .onChange(of: appState.selectedTable) { _, newValue in
            // Only load when active to avoid unnecessary work
            guard isActive else {
                // Mark that we need to reload when becoming active
                hasLoadedInitialData = false
                tableStructure = nil
                return
            }
            if let table = newValue {
                loadStructure(schemaName: table.schema, tableName: table.name)
            } else {
                tableStructure = nil
            }
        }
        .onChange(of: isActive) { _, newValue in
            // When becoming active, load data if we haven't already
            if newValue && !hasLoadedInitialData {
                if let table = appState.selectedTable {
                    loadStructure(schemaName: table.schema, tableName: table.name)
                }
            }
        }
    }

    private func loadStructure(schemaName: String, tableName: String) {
        isLoading = true
        errorMessage = ""
        hasLoadedInitialData = true

        Task {
            do {
                let structure = try await pgApi.fetchTableStructure(
                    schemaName: schemaName,
                    tableName: tableName
                )
                await MainActor.run {
                    self.tableStructure = structure
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func refreshStructure() {
        if let table = appState.selectedTable {
            loadStructure(schemaName: table.schema, tableName: table.name)
        }
    }
}
