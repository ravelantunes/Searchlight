//
//  AddConstraintSheet.swift
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

struct AddConstraintSheet: View {
    let schemaName: String
    let tableName: String
    let columns: [ColumnDefinition]
    let onSave: () -> Void

    @EnvironmentObject var pgApi: PostgresDatabaseAPI
    @Environment(\.dismiss) private var dismiss

    @State private var constraintName = ""
    @State private var constraintType: ConstraintType = .unique
    @State private var selectedColumns: Set<String> = []
    @State private var checkExpression = ""

    // Foreign key specific
    @State private var fkSchema = ""
    @State private var fkTable = ""
    @State private var fkColumn = ""
    @State private var onDeleteAction = "NO ACTION"
    @State private var onUpdateAction = "NO ACTION"

    @State private var isProcessing = false
    @State private var errorMessage: String?

    private let supportedTypes: [ConstraintType] = [.unique, .check, .foreignKey]
    private let referentialActions = ["NO ACTION", "CASCADE", "SET NULL", "SET DEFAULT", "RESTRICT"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Add Constraint")
                    .fontWeight(.semibold)
                Spacer()
                Button("Add") { addConstraint() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isProcessing)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    GroupedSectionView(title: "Constraint Definition") {
                        FormTextField(label: "Name", text: $constraintName, placeholder: "constraint_name")

                        FormFieldRow(label: "Type", showDivider: false) {
                            Picker("", selection: $constraintType) {
                                ForEach(supportedTypes, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    if constraintType == .check {
                        GroupedSectionView(title: "Check Expression") {
                            FormTextField(
                                label: "Expression",
                                text: $checkExpression,
                                placeholder: "column_name > 0",
                                showDivider: false
                            )
                        }
                    } else {
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
                    }

                    if constraintType == .foreignKey {
                        GroupedSectionView(title: "References") {
                            FormTextField(label: "Schema", text: $fkSchema, placeholder: schemaName)
                            FormTextField(label: "Table", text: $fkTable, placeholder: "referenced_table")
                            FormTextField(label: "Column", text: $fkColumn, placeholder: "referenced_column")

                            FormFieldRow(label: "On Delete") {
                                Picker("", selection: $onDeleteAction) {
                                    ForEach(referentialActions, id: \.self) { action in
                                        Text(action).tag(action)
                                    }
                                }
                                .labelsHidden()
                            }

                            FormFieldRow(label: "On Update", showDivider: false) {
                                Picker("", selection: $onUpdateAction) {
                                    ForEach(referentialActions, id: \.self) { action in
                                        Text(action).tag(action)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
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
        .frame(width: 480, height: constraintType == .foreignKey ? 600 : 450)
        .onAppear {
            fkSchema = schemaName
        }
    }

    private var isValid: Bool {
        guard !constraintName.isEmpty else { return false }

        switch constraintType {
        case .check:
            return !checkExpression.isEmpty
        case .foreignKey:
            return !selectedColumns.isEmpty && !fkTable.isEmpty && !fkColumn.isEmpty
        case .unique, .primaryKey:
            return !selectedColumns.isEmpty
        case .exclusion:
            return false
        }
    }

    private func addConstraint() {
        isProcessing = true
        errorMessage = nil

        let columnsArray = columns
            .filter { selectedColumns.contains($0.name) }
            .map { $0.name }

        let fkRef: ForeignKeyReference?
        if constraintType == .foreignKey {
            fkRef = ForeignKeyReference(
                schemaName: fkSchema.isEmpty ? schemaName : fkSchema,
                tableName: fkTable,
                columnName: fkColumn
            )
        } else {
            fkRef = nil
        }

        Task {
            do {
                try await pgApi.addConstraint(
                    schemaName: schemaName,
                    tableName: tableName,
                    constraintName: constraintName,
                    constraintType: constraintType,
                    columns: columnsArray,
                    checkExpression: constraintType == .check ? checkExpression : nil,
                    foreignKeyReference: fkRef,
                    onDelete: constraintType == .foreignKey ? onDeleteAction : nil,
                    onUpdate: constraintType == .foreignKey ? onUpdateAction : nil
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
