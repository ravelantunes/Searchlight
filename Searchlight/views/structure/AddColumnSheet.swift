//
//  AddColumnSheet.swift
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

struct AddColumnSheet: View {
    let schemaName: String
    let tableName: String
    let onSave: () -> Void

    @EnvironmentObject var pgApi: PostgresDatabaseAPI
    @Environment(\.dismiss) private var dismiss

    @State private var columnName = ""
    @State private var selectedType = "varchar"
    @State private var typeLength: String = ""
    @State private var isNullable = true
    @State private var defaultValue = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private let commonTypes = [
        "varchar", "text", "integer", "bigint", "smallint",
        "boolean", "date", "timestamp", "timestamptz",
        "numeric", "real", "double precision", "uuid", "jsonb"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Add Column")
                    .fontWeight(.semibold)
                Spacer()
                Button("Add") { addColumn() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(columnName.isEmpty || isProcessing)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    GroupedSectionView(title: "Column Definition") {
                        FormTextField(label: "Name", text: $columnName, placeholder: "column_name")

                        FormFieldRow(label: "Type") {
                            Picker("", selection: $selectedType) {
                                ForEach(commonTypes, id: \.self) { type in
                                    Text(type).tag(type)
                                }
                            }
                            .labelsHidden()
                        }

                        if ["varchar", "char"].contains(selectedType) {
                            FormTextField(label: "Length", text: $typeLength, placeholder: "255 (optional)")
                        }

                        if selectedType == "numeric" {
                            FormTextField(label: "Precision", text: $typeLength, placeholder: "10,2 (optional)")
                        }

                        FormFieldRow(label: "Nullable") {
                            Toggle("", isOn: $isNullable)
                                .labelsHidden()
                        }

                        FormTextField(
                            label: "Default",
                            text: $defaultValue,
                            placeholder: "Optional default value",
                            showDivider: false
                        )
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
        .frame(width: 450, height: 400)
    }

    private func addColumn() {
        isProcessing = true
        errorMessage = nil

        let fullType: String
        if !typeLength.isEmpty {
            if ["varchar", "char"].contains(selectedType) {
                fullType = "\(selectedType)(\(typeLength))"
            } else if selectedType == "numeric" {
                fullType = "\(selectedType)(\(typeLength))"
            } else {
                fullType = selectedType
            }
        } else {
            fullType = selectedType
        }

        Task {
            do {
                try await pgApi.addColumn(
                    schemaName: schemaName,
                    tableName: tableName,
                    columnName: columnName,
                    dataType: fullType,
                    isNullable: isNullable,
                    defaultValue: defaultValue.isEmpty ? nil : defaultValue
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
