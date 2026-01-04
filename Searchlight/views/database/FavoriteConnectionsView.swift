//
//  FavoriteConnectionsView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 9/25/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation
import SwiftUI

struct FavoriteConnectionsView: View {

    @StateObject private var favoriteStore = FavoritesStore.shared
    @Binding var selectedConnection: DatabaseConnectionConfiguration
    @State private var selectedConnectionID: String?

    private let newConnectionConfig = DatabaseConnectionConfiguration(
        name: "",
        host: "",
        database: "",
        user: "",
        password: "",
        ssl: true,
        favorited: false,
        sshTunnel: nil
    )

    private var isNewConnectionSelected: Bool {
        selectedConnection.name.isEmpty && !selectedConnection.favorited
    }

    var body: some View {
        List(selection: $selectedConnectionID) {
            Section {
                if favoriteStore.favorites.isEmpty {
                    EmptyFavoritesView()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(favoriteStore.favorites) { connection in
                        favoriteRow(for: connection)
                            .tag(connection.id)
                    }
                }
            } header: {
                HStack {
                    Text("Favorites")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Spacer()

                    if !favoriteStore.favorites.isEmpty {
                        Text("\(favoriteStore.favorites.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }
                }
                .padding(.bottom, Spacing.xxs)
            }
            .listRowInsets(EdgeInsets(
                top: 2,
                leading: Spacing.sm,
                bottom: 2,
                trailing: Spacing.lg
            ))
        }
        .listStyle(.sidebar)
        .onChange(of: selectedConnectionID) { _, newID in
            if let newID, let connection = favoriteStore.favorites.first(where: { $0.id == newID }) {
                selectedConnection = connection
            }
        }
        .onChange(of: selectedConnection) { _, newConnection in
            if newConnection.favorited {
                selectedConnectionID = newConnection.id
            } else {
                selectedConnectionID = nil
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Button {
                selectedConnection = newConnectionConfig
            } label: {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                    Text("New Connection")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    private func favoriteRow(for connection: DatabaseConnectionConfiguration) -> some View {
        FavoriteConnectionRow(connection: connection, isSelected: selectedConnectionID == connection.id)
            .onDoubleClick {
                var connectionCopy = connection
                connectionCopy.connectRightAway = true
                selectedConnection = connectionCopy
            }
            .contextMenu {
                Button {
                    var connectionCopy = connection
                    connectionCopy.connectRightAway = true
                    selectedConnection = connectionCopy
                } label: {
                    Label("Connect", systemImage: "bolt.fill")
                }

                Divider()

                Button {
                    // Future: duplicate functionality
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .disabled(true)

                Button(role: .destructive) {
                    favoriteStore.removeFavorite(databaseConnectionConfiguration: connection)
                } label: {
                    Label("Delete \"\(connection.name)\"", systemImage: "trash")
                }
            }
    }

    func reselectLastSelectedDatabase() {
        let lastSelectedDatabase = self.favoriteStore.loadLastSelectedDatabase()
        if let selectedDatabase = self.favoriteStore.favorites.first(where: { $0.name == lastSelectedDatabase }) {
            DispatchQueue.main.async {
                self.selectedConnection = selectedDatabase
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedConnection = DatabaseConnectionConfiguration(
        name: "",
        host: "",
        database: "",
        user: "",
        password: "",
        ssl: true,
        favorited: false,
        sshTunnel: nil
    )

    FavoriteConnectionsView(selectedConnection: $selectedConnection)
        .frame(width: 260, height: 400)
}
