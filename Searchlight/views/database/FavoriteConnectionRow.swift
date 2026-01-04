//
//  FavoriteConnectionRow.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/4/26.
//
//  Copyright (c) 2026 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI
import AppKit

/// A view modifier that adds double-click detection using AppKit
/// This is needed because I didn't find a solution on SwiftUI to both handle single tap selection and double-tap for starting a connection.
struct DoubleClickHandler: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DoubleClickView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DoubleClickView)?.onDoubleClick = onDoubleClick
    }

    class DoubleClickView: NSView {
        var onDoubleClick: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            if event.clickCount == 2 {
                onDoubleClick?()
            }
        }
    }
}

extension View {
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        overlay(DoubleClickHandler(onDoubleClick: action))
    }
}

/// Enhanced favorite connection row with color indicator and subtitle
struct FavoriteConnectionRow: View {
    let connection: DatabaseConnectionConfiguration
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Color indicator circle
            Circle()
                .fill(connection.favoriteColor.map { hexToColor($0) } ?? Color.accentColor)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: isSelected ? 1 : 0)
                )
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(connectionSubtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // SSH indicator badge
            if connection.sshTunnel?.enabled == true {
                Image(systemName: "lock.shield")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private var connectionSubtitle: String {
        if connection.database.isEmpty {
            return connection.host.isEmpty ? "Not configured" : connection.host
        }
        return "\(connection.host) / \(connection.database)"
    }

    private func hexToColor(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

#Preview {
    List {
        FavoriteConnectionRow(
            connection: DatabaseConnectionConfiguration(
                name: "Production DB",
                host: "db.example.com",
                database: "myapp_prod",
                user: "admin",
                password: "secret",
                ssl: true,
                favorited: true,
                sshTunnel: SSHTunnelConfiguration(enabled: true, host: "ssh.example.com", port: 22, user: "admin", keyPath: "~/.ssh/id_rsa", keyBookmarkData: nil),
                favoriteColor: "#FF6B6B",
                favoriteIcon: "star.fill"
            )
        )

        FavoriteConnectionRow(
            connection: DatabaseConnectionConfiguration(
                name: "Local Development",
                host: "localhost",
                database: "myapp_dev",
                user: "postgres",
                password: "",
                ssl: false,
                favorited: true,
                sshTunnel: nil,
                favoriteColor: "#51CF66",
                favoriteIcon: "star.fill"
            )
        )

        FavoriteConnectionRow(
            connection: DatabaseConnectionConfiguration(
                name: "Staging",
                host: "staging.example.com",
                database: "myapp_staging",
                user: "deploy",
                password: "secret",
                ssl: true,
                favorited: true,
                sshTunnel: nil,
                favoriteColor: nil,
                favoriteIcon: nil
            )
        )
    }
    .listStyle(.sidebar)
    .frame(width: 260)
}
