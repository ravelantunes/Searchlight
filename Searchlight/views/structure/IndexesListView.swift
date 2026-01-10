//
//  IndexesListView.swift
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
import AppKit

struct IndexesListView: View {
    let indexes: [IndexDefinition]
    let schemaName: String
    let tableName: String
    let columns: [ColumnDefinition]
    let onRefresh: () -> Void

    @EnvironmentObject var pgApi: PostgresDatabaseAPI
    @State private var showAddIndexSheet = false
    @State private var indexToDelete: IndexDefinition?
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { showAddIndexSheet = true }) {
                    Label("Add Index", systemImage: "plus")
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

            if indexes.isEmpty {
                Spacer()
                Text("No indexes defined")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(indexes) { index in
                        IndexRowView(index: index)
                            .contextMenu {
                                Button("Copy Definition") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(index.indexDefinition, forType: .string)
                                }
                                Divider()
                                Button("Drop Index", role: .destructive) {
                                    indexToDelete = index
                                    showDeleteConfirmation = true
                                }
                                .disabled(index.isPrimaryKey)
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showAddIndexSheet) {
            AddIndexSheet(
                schemaName: schemaName,
                tableName: tableName,
                columns: columns,
                onSave: { onRefresh() }
            )
        }
        .confirmationDialog(
            "Drop Index",
            isPresented: $showDeleteConfirmation,
            presenting: indexToDelete
        ) { index in
            Button("Drop \"\(index.name)\"", role: .destructive) {
                dropIndex(index)
            }
            Button("Cancel", role: .cancel) {}
        } message: { index in
            Text("Are you sure you want to drop the index \"\(index.name)\"? This may affect query performance.")
        }
    }

    private func dropIndex(_ index: IndexDefinition) {
        errorMessage = nil
        Task {
            do {
                try await pgApi.dropIndex(schemaName: schemaName, indexName: index.name)
                await MainActor.run { onRefresh() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct IndexRowView: View {
    let index: IndexDefinition

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    if index.isPrimaryKey {
                        Image(systemName: "key.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                            .help("Primary Key Index")
                    }
                    Text(index.name)
                        .fontWeight(index.isPrimaryKey ? .semibold : .regular)
                }

                Text(index.columns.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if index.isUnique && !index.isPrimaryKey {
                Text("UNIQUE")
                    .font(.caption)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(CornerRadius.small)
            }

            Text(index.indexType)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, Spacing.xxs)
    }
}
