//
//  AddIndexSheet.swift
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

struct AddIndexSheet: View {
    let schemaName: String
    let tableName: String
    let columns: [ColumnDefinition]
    let onSave: () -> Void

    @EnvironmentObject var pgApi: PostgresDatabaseAPI
    @Environment(\.dismiss) private var dismiss

    @State private var indexName = ""
    @State private var selectedColumns: Set<String> = []
    @State private var isUnique = false
    @State private var indexType = "btree"
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private let indexTypes = ["btree", "hash", "gist", "gin", "brin"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Create Index")
                    .fontWeight(.semibold)
                Spacer()
                Button("Create") { createIndex() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(indexName.isEmpty || selectedColumns.isEmpty || isProcessing)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    GroupedSectionView(title: "Index Definition") {
                        FormTextField(label: "Name", text: $indexName, placeholder: "idx_\(tableName)_column")

                        FormFieldRow(label: "Type") {
                            Picker("", selection: $indexType) {
                                ForEach(indexTypes, id: \.self) { type in
                                    Text(type).tag(type)
                                }
                            }
                            .labelsHidden()
                        }

                        FormFieldRow(label: "Unique", showDivider: false) {
                            Toggle("", isOn: $isUnique)
                                .labelsHidden()
                        }
                    }

                    GroupedSectionView(title: "Columns") {
                        ForEach(columns) { column in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { selectedColumns.contains(column.name) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedColumns.insert(column.name)
                                        } else {
                                            selectedColumns.remove(column.name)
                                        }
                                    }
                                )) {
                                    HStack {
                                        Text(column.name)
                                        Text(column.fullTypeName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)

                            if column.id != columns.last?.id {
                                Divider()
                                    .padding(.leading, Spacing.md)
                            }
                        }
                    }

                    if selectedColumns.count > 1 {
                        Text("Selected columns: \(selectedColumns.sorted().joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
        }
        .frame(width: 450, height: 500)
        .onAppear {
            // Generate default index name
            indexName = "idx_\(tableName)_"
        }
    }

    private func createIndex() {
        isProcessing = true
        errorMessage = nil

        let columnsArray = columns
            .filter { selectedColumns.contains($0.name) }
            .map { $0.name }

        Task {
            do {
                try await pgApi.createIndex(
                    schemaName: schemaName,
                    tableName: tableName,
                    indexName: indexName,
                    columns: columnsArray,
                    isUnique: isUnique,
                    indexType: indexType
                )
                await MainActor.run {
                    onSave()
                    dismiss()
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
