//
//  DatabaseConnectionConfiguration.swift
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

// SSH Tunnel Configuration
struct SSHTunnelConfiguration: Codable, Hashable {
    let enabled: Bool
    let host: String
    let port: Int
    let user: String
    let keyPath: String
    let keyPassphrase: String?  // Reserved for future use - macOS SSH uses Keychain automatically
    let keyBookmarkData: Data?  // Security-scoped bookmark for persistent file access
}

// Struct to wrap the database configuration in an API abstract way
struct DatabaseConnectionConfiguration: Codable, Identifiable, Hashable {
    
    // Id = name
    var id: String { name }
    
    // The name of the configuration provided by the user. This is just used to save on favorites, and not on the actual connection
    let name: String
    
    // Database host (without schema or protocol)
    let host: String
    
    // Database port
    var port: Int = 5432
    
    // The name of the database schema
    let database: String
    
    // Database user
    let user: String
    
    // Database password
    let password: String
    
    // Wether to use SSL or not
    let ssl: Bool
    
    // Whether the current connection is a favorited connection
    let favorited: Bool

    // SSH Tunnel configuration (optional)
    let sshTunnel: SSHTunnelConfiguration?

    // TODO: this is a bit of a hack, and can be better implemented by moving the connection out of the DatabaseConnection View
    // This is used as an internal shortcut to notify the DatabaseConnectionView to try to connect right away.
    var connectRightAway: Bool = false
}

// Creates a copy of the struct, overriding the database name with the one passed as argument.
// This is to help with the database change funcionality, where we need to create a new connection.
extension DatabaseConnectionConfiguration {
    func copyWithDatabaseChangedTo(database newDatabase: String) -> Self {
        return DatabaseConnectionConfiguration(name: id, host: host, database: newDatabase, user: user, password: password, ssl: ssl, favorited: favorited, sshTunnel: sshTunnel)
    }
}

class DatabaseConnectionConfigurationWrapper: ObservableObject, Equatable {
    @Published var configuration: DatabaseConnectionConfiguration?
    
    init(configuration: DatabaseConnectionConfiguration) {
        self.configuration = configuration
    }
    
    static func == (lhs: DatabaseConnectionConfigurationWrapper, rhs: DatabaseConnectionConfigurationWrapper) -> Bool {
        return lhs.configuration == rhs.configuration
    }
}
