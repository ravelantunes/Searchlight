//
//  AppState.swift
//  Searchlight
//
//  Created by Ravel Antunes on 7/6/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation

@MainActor
class AppState: ObservableObject {
    @Published var databases: [String] = [""]
    @Published var selectedDatabase: String?
    @Published var selectedTable: Table?
    @Published var selectedDatabaseConnectionConfiguration = DatabaseConnectionConfiguration(name: "", host: "", database: "", user: "", password: "", ssl: false, favorited: false, sshTunnel: nil)
}
