//
//  EditColumnSheet.swift
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

struct EditColumnSheet: View {
    let schemaName: String
    let tableName: String
    let column: ColumnDefinition
    let onSave: () -> Void

    @EnvironmentObject var pgApi: PostgresDatabaseAPI
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String
    @State private var newType: String
    @State private var isNullable: Bool
    @State private var defaultValue: String
    @State private var isProcessing = false
    @State private var errorMessage: String?

    init(schemaName: String, tableName: String, column: ColumnDefinition, onSave: @escaping () -> Void) {
        self.schemaName = schemaName
        self.tableName = tableName
        self.column = column
        self.onSave = onSave
        _newName = State(initialValue: column.name)
        _newType = State(initialValue: column.fullTypeName)
        _isNullable = State(initialValue: column.isNullable)
        _defaultValue = State(initialValue: column.columnDefault ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Edit Column: \(column.name)")
                    .fontWeight(.semibold)
                Spacer()
                Button("Save") { saveChanges() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isProcessing)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    GroupedSectionView(title: "Rename Column") {
                        FormTextField(label: "Name", text: $newName, placeholder: "column_name", showDivider: false)
                    }

                    GroupedSectionView(title: "Change Type") {
                        FormTextField(label: "Type", text: $newType, placeholder: "varchar(255)", showDivider: false)
                    }

                    GroupedSectionView(title: "Constraints") {
                        FormFieldRow(label: "Nullable") {
                            Toggle("", isOn: $isNullable)
                                .labelsHidden()
                        }
                        FormTextField(label: "Default", text: $defaultValue, placeholder: "Default value", showDivider: false)
                    }

                    if column.isPrimaryKey {
                        Text("Note: This column is a primary key. Some modifications may be restricted.")
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
        .frame(width: 450, height: 450)
    }

    private func saveChanges() {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                // Rename if changed
                var currentName = column.name
                if newName != column.name {
                    try await pgApi.renameColumn(
                        schemaName: schemaName,
                        tableName: tableName,
                        oldName: column.name,
                        newName: newName
                    )
                    currentName = newName
                }

                // Change type if changed
                if newType != column.fullTypeName {
                    try await pgApi.alterColumnType(
                        schemaName: schemaName,
                        tableName: tableName,
                        columnName: currentName,
                        newType: newType
                    )
                }

                // Change nullability if changed
                if isNullable != column.isNullable {
                    try await pgApi.alterColumnNullability(
                        schemaName: schemaName,
                        tableName: tableName,
                        columnName: currentName,
                        isNullable: isNullable
                    )
                }

                // Change default if changed
                let newDefault = defaultValue.isEmpty ? nil : defaultValue
                if newDefault != column.columnDefault {
                    try await pgApi.alterColumnDefault(
                        schemaName: schemaName,
                        tableName: tableName,
                        columnName: currentName,
                        defaultValue: newDefault
                    )
                }

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
