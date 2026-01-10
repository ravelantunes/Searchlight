//
//  ConstraintsListView.swift
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

struct ConstraintsListView: View {
    let constraints: [ConstraintDefinition]
    let schemaName: String
    let tableName: String
    let columns: [ColumnDefinition]
    let onRefresh: () -> Void

    @EnvironmentObject var pgApi: PostgresDatabaseAPI
    @State private var showAddConstraintSheet = false
    @State private var constraintToDelete: ConstraintDefinition?
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { showAddConstraintSheet = true }) {
                    Label("Add Constraint", systemImage: "plus")
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

            if constraints.isEmpty {
                Spacer()
                Text("No constraints defined")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(constraints) { constraint in
                        ConstraintRowView(constraint: constraint)
                            .contextMenu {
                                Button("Drop Constraint", role: .destructive) {
                                    constraintToDelete = constraint
                                    showDeleteConfirmation = true
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showAddConstraintSheet) {
            AddConstraintSheet(
                schemaName: schemaName,
                tableName: tableName,
                columns: columns,
                onSave: { onRefresh() }
            )
        }
        .confirmationDialog(
            "Drop Constraint",
            isPresented: $showDeleteConfirmation,
            presenting: constraintToDelete
        ) { constraint in
            Button("Drop \"\(constraint.name)\"", role: .destructive) {
                dropConstraint(constraint)
            }
            Button("Cancel", role: .cancel) {}
        } message: { constraint in
            Text("Are you sure you want to drop the constraint \"\(constraint.name)\"? This may affect data integrity.")
        }
    }

    private func dropConstraint(_ constraint: ConstraintDefinition) {
        errorMessage = nil
        Task {
            do {
                try await pgApi.dropConstraint(
                    schemaName: schemaName,
                    tableName: tableName,
                    constraintName: constraint.name
                )
                await MainActor.run { onRefresh() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct ConstraintRowView: View {
    let constraint: ConstraintDefinition

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(constraint.name)

                HStack(spacing: Spacing.xs) {
                    Text(constraint.columns.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let fkRef = constraint.foreignKeyReference {
                        Text("-> \(fkRef.tableName).\(fkRef.columnName)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    if let checkExpr = constraint.checkExpression {
                        Text(truncateExpression(checkExpr))
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                            .help(checkExpr)
                    }
                }
            }

            Spacer()

            // Actions indicator for FK
            if constraint.constraintType == .foreignKey {
                if let onDelete = constraint.onDelete, onDelete != "NO ACTION" {
                    Text("DEL: \(onDelete)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Text(constraint.constraintType.rawValue)
                .font(.caption)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(colorForConstraintType(constraint.constraintType).opacity(0.2))
                .cornerRadius(CornerRadius.small)
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func colorForConstraintType(_ type: ConstraintType) -> Color {
        switch type {
        case .primaryKey: return .yellow
        case .foreignKey: return .blue
        case .unique: return .purple
        case .check: return .orange
        case .exclusion: return .green
        }
    }

    private func truncateExpression(_ expr: String) -> String {
        if expr.count > 30 {
            return String(expr.prefix(30)) + "..."
        }
        return expr
    }
}
