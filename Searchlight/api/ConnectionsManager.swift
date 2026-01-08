//
//  ConnectionsManager.swift
//  Searchlight
//
//  Created by Ravel Antunes on 9/28/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

enum ConnectionManagerError: Error {
    case connectionNotFound(String)
}


// This class should encapsulate the management of multiple connections (multiple window, switch schema, etc)
@MainActor
class ConnectionsManager {
    
    private var connectionMap: [String: PostgresConnection] = [:]
    private var configMap: [String: DatabaseConnectionConfiguration] = [:]
    private var selectedConnection: PostgresConnection?
    
    // Keep a reference to the first connection to be used to create different connections during database changes
    private var templateConnection: DatabaseConnectionConfiguration?

    /// The Postgres Language Server manager for SQL editor features
    let lspManager = PostgresLSPManager()

    var connection: PostgresConnection {
        guard selectedConnection != nil else {
            fatalError("No connection has been selected yet")
        }
        return selectedConnection!
    }

    // The SSH tunnel local port of the currently selected connection, if any
    var tunnelLocalPort: Int? {
        return selectedConnection?.tunnelLocalPort
    }

    func initializeConnection(configuration: DatabaseConnectionConfiguration) async throws -> PostgresConnection {
        if templateConnection == nil {
            templateConnection = configuration
        }

        if let existing = connectionMap.removeValue(forKey: configuration.database) {
            configMap.removeValue(forKey: configuration.database)
            if selectedConnection === existing {
                selectedConnection = nil
            }
            await existing.close()
        }

        let connection = try await PostgresConnection(configuration: configuration)
        connectionMap[configuration.database] = connection
        configMap[configuration.database] = configuration
        return connection
    }


    func switchConnectionTo(database: String) async throws {
        if let connection = connectionMap[database] {
            selectedConnection = connection
            await restartLSP(forDatabase: database)
            return
        }

        if let newConfiguration = templateConnection?.copyWithDatabaseChangedTo(database: database) {
            let connection = try await initializeConnection(configuration: newConfiguration)
            selectedConnection = connection
            await restartLSP(forDatabase: database)
            return
        }

        throw ConnectionManagerError.connectionNotFound(database)
    }

    /// Restarts the LSP for the specified database connection
    private func restartLSP(forDatabase database: String) async {
        guard let connection = connectionMap[database],
              let config = configMap[database] else {
            return
        }

        do {
            try await lspManager.restart(config: config, tunnelPort: connection.tunnelLocalPort)
        } catch {
            // LSP failure is non-fatal - editor still works without it
            print("[LSP] Failed to restart language server: \(error)")
        }
    }

    func connection(database: String) throws -> PostgresConnection {
        guard let connection = connectionMap[database] else {
            // TODO: throw error
            throw ConnectionManagerError.connectionNotFound(database)
        }
        return connection
    }

    func closeConnection(for database: String) async {
        guard let connection = connectionMap.removeValue(forKey: database) else { return }
        configMap.removeValue(forKey: database)

        if selectedConnection === connection {
            selectedConnection = nil
        }
        
        await connection.close()
    }

    func closeAllConnections() async {
        let connections = Array(connectionMap.values)
        connectionMap.removeAll()
        configMap.removeAll()
        selectedConnection = nil

        for connection in connections {
            await connection.close()
        }
    }

    deinit {
        // Best-effort async cleanup without capturing self
        let connections = Array(connectionMap.values)
        for connection in connections {
            Task {
                await connection.close()
            }
        }
    }
}

@MainActor
class ConnectionsManagerObservableWrapper: ObservableObject {
    let connectionManager = ConnectionsManager()
}
