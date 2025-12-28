//
//  FavoritesStore.swift
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

// Handles interaction with UserDefaults as the mechanism to store favorite lists information
class FavoritesStore: ObservableObject {
    
    static let shared = FavoritesStore()
    let suiteName = "com.searchlight.Searchlight.favorites"
    private let FavoriteDatabasesListKey: String = "favoriteDatabasesList"
    
    @Published var favorites = [DatabaseConnectionConfiguration]()

    init() {
        refresh()
    }

    private func refresh() {
        favorites = Array(loadFavorites()).sorted(by: { $0.name < $1.name })
    }
    
    func saveFavorite(databaseConnectionConfiguration: DatabaseConnectionConfiguration) {
        var currentList = loadFavorites()

        // Tries to find existing connection with the same name. If it exists, just replce it
        if let existingIndex = currentList.firstIndex(where:{ $0.name == databaseConnectionConfiguration.name }) {
            currentList.remove(at: existingIndex)
        }
        currentList.insert(databaseConnectionConfiguration)

        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(currentList) {
            UserDefaults.standard.set(encoded, forKey: FavoriteDatabasesListKey)
            UserDefaults.standard.synchronize()
        } else {
            print("FavoritesStore: Failed to encode favorites")
        }

        refresh()
    }
    
    func saveLastSelectedDatabaseName(databaseConnectionConfigurationName: String) {
        UserDefaults.standard.set(databaseConnectionConfigurationName, forKey: "lastSelectedDatabase")
    }
    
    func removeFavorite(databaseConnectionConfiguration: DatabaseConnectionConfiguration) {
        let currentList = loadFavorites()
        let newList = currentList.subtracting([databaseConnectionConfiguration])
        
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(newList) {
            UserDefaults.standard.set(encoded, forKey: FavoriteDatabasesListKey)
            UserDefaults.standard.synchronize()
        }        
        refresh()
    }
    
    func loadFavorites() -> Set<DatabaseConnectionConfiguration> {
        let decoder = JSONDecoder()

        guard let data = UserDefaults.standard.data(forKey: FavoriteDatabasesListKey) else {
            print("No favorites data found in UserDefaults. Returning empty set.")
            return Set()
        }

        guard let decoded = try? decoder.decode(Set<DatabaseConnectionConfiguration>.self, from: data) else {
            print("Failed to decode favorites from \(data.count) bytes. Returning empty set.")
            return Set()
        }

        return decoded
    }
    
    func loadLastSelectedDatabase() -> String? {
        UserDefaults.standard.string(forKey: "lastSelectedDatabase")
    }
}
