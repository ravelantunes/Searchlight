//
//  ConnectionStatusView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/4/26.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

/// Connection validity state for status display
enum ConnectionValidityState {
    case untested
    case testing
    case valid
    case invalid(String)
}

/// A contextual status view that displays connection test results
struct ConnectionStatusView: View {
    let state: ConnectionValidityState

    var body: some View {
        Group {
            switch state {
            case .untested:
                EmptyView()

            case .testing:
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Testing connection...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

            case .valid:
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connection successful")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }

            case .invalid(let message):
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(statusBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    @ViewBuilder
    private var statusBackground: some View {
        switch state {
        case .untested:
            Color.clear
        case .testing:
            Color.secondary.opacity(0.1)
        case .valid:
            Color.green.opacity(0.1)
        case .invalid:
            Color.red.opacity(0.1)
        }
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        ConnectionStatusView(state: .testing)
        ConnectionStatusView(state: .valid)
        ConnectionStatusView(state: .invalid("Connection refused: Could not connect to localhost:5432"))
    }
    .padding()
    .frame(width: 400)
}
