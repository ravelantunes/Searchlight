//
//  ColumnsListView.swift
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

struct ColumnsListView: View {
    let columns: [ColumnDefinition]
    let schemaName: String
    let tableName: String
    let onRefresh: () -> Void

    @EnvironmentObject var pgApi: PostgresDatabaseAPI
    @State private var showAddColumnSheet = false
    @State private var columnToEdit: ColumnDefinition?
    @State private var columnToDelete: ColumnDefinition?
    @State private var showDeleteConfirmation = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: { showAddColumnSheet = true }) {
                    Label("Add Column", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)

            Divider()

            // Column list
            List {
                ForEach(columns) { column in
                    StructureColumnRowView(column: column)
                        .contextMenu {
                            Button("Edit Column...") {
                                columnToEdit = column
                            }
                            Divider()
                            Button("Delete Column", role: .destructive) {
                                columnToDelete = column
                                showDeleteConfirmation = true
                            }
                            .disabled(column.isPrimaryKey)
                        }
                }
            }
            .listStyle(.inset)
        }
        .sheet(isPresented: $showAddColumnSheet) {
            AddColumnSheet(
                schemaName: schemaName,
                tableName: tableName,
                onSave: {
                    onRefresh()
                }
            )
        }
        .sheet(item: $columnToEdit) { column in
            EditColumnSheet(
                schemaName: schemaName,
                tableName: tableName,
                column: column,
                onSave: { onRefresh() }
            )
        }
        .confirmationDialog(
            "Delete Column",
            isPresented: $showDeleteConfirmation,
            presenting: columnToDelete
        ) { column in
            Button("Delete \"\(column.name)\"", role: .destructive) {
                deleteColumn(column)
            }
            Button("Cancel", role: .cancel) {}
        } message: { column in
            Text("Are you sure you want to delete the column \"\(column.name)\"? This action cannot be undone and will permanently remove all data in this column.")
        }
    }

    private func deleteColumn(_ column: ColumnDefinition) {
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                try await pgApi.dropColumn(
                    schemaName: schemaName,
                    tableName: tableName,
                    columnName: column.name
                )
                await MainActor.run {
                    isProcessing = false
                    onRefresh()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct StructureColumnRowView: View {
    let column: ColumnDefinition

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Column name with indicators
            HStack(spacing: Spacing.xs) {
                if column.isPrimaryKey {
                    Image(systemName: "key.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                        .help("Primary Key")
                }
                if column.isForeignKey {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                        .help("Foreign Key")
                }
                Text(column.name)
                    .fontWeight(column.isPrimaryKey ? .semibold : .regular)
            }
            .frame(minWidth: 120, alignment: .leading)

            Spacer()

            // Type
            Text(column.fullTypeName)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 100, alignment: .leading)

            // Nullable indicator
            Text(column.isNullable ? "NULL" : "NOT NULL")
                .font(.caption)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(column.isNullable ? Color.gray.opacity(0.2) : Color.orange.opacity(0.2))
                .cornerRadius(CornerRadius.small)

            // Default value
            if let defaultValue = column.columnDefault {
                Text("= \(truncateDefault(defaultValue))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
                    .help(defaultValue)
            }

            // FK reference
            if let fkRef = column.foreignKeyReference {
                Text("-> \(fkRef.tableName).\(fkRef.columnName)")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func truncateDefault(_ value: String) -> String {
        if value.count > 20 {
            return String(value.prefix(20)) + "..."
        }
        return value
    }
}
