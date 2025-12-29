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
    @State private var newConnectionSelected = false

    
    var body: some View {
        List(selection: $selectedConnection) {            
            NavigationLink(value: DatabaseConnectionConfiguration(name: "", host: "", database: "", user: "", password: "", ssl: true, favorited: false, sshTunnel: nil)) {
                Label("New Connection", systemImage: "plus")
            }
            Section("Favorites") {
                ForEach(favoriteStore.favorites) { favoriteConnection in
                    NavigationLink(value: favoriteConnection) {
                        Label {
                            Text(favoriteConnection.name)
                        } icon: {
                            Image(systemName: "star.fill")
                                .foregroundColor(favoriteConnection.favoriteColor != nil ? hexToColor(favoriteConnection.favoriteColor!) : .secondary)
                        }
                    }
                    .onTapGesture(count: 2) {
                        // Make copy of favoriteConnection so we can append connectRightAway to the struct
                        let favoriteConnectionCopy = DatabaseConnectionConfiguration(
                            name: favoriteConnection.name,
                            host: favoriteConnection.host,
                            database: favoriteConnection.database,
                            user: favoriteConnection.user,
                            password: favoriteConnection.password,
                            ssl: favoriteConnection.ssl,
                            favorited: favoriteConnection.favorited,
                            sshTunnel: favoriteConnection.sshTunnel,
                            connectRightAway: true,
                            favoriteColor: favoriteConnection.favoriteColor,
                            favoriteIcon: favoriteConnection.favoriteIcon
                        )
                        selectedConnection = favoriteConnectionCopy
                    }
                    .simultaneousGesture(TapGesture(count: 1).onEnded {
                        selectedConnection = favoriteConnection
                    })
                    .contextMenu {
                        Button("delete \(favoriteConnection.name)") {
                            favoriteStore.removeFavorite(databaseConnectionConfiguration: favoriteConnection)
                        }
                    }
                }
            }
            
        }
        .onAppear(perform: reselectLastSelectedDatabase)
    }
    
    func reselectLastSelectedDatabase() {
        let lastSelectedDatabase = self.favoriteStore.loadLastSelectedDatabase()
        if let selectedDatabase = self.favoriteStore.favorites.first(where: { $0.name == lastSelectedDatabase }) {
            DispatchQueue.main.async {
                self.selectedConnection = selectedDatabase
            }
        }
    }

    // Helper function for color conversion
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
