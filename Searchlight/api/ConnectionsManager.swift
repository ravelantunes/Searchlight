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
class ConnectionsManager {
    
    private var connectionMap: [String: PostgresConnection] = [:]
    private var selectedConnection: PostgresConnection?
    
    // Keep a reference to the first connection to be used to create different connections during database changes
    private var templateConnection: DatabaseConnectionConfiguration?
    
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
            if selectedConnection === existing {
                selectedConnection = nil
            }
            await existing.close()
        }

        let connection = try await PostgresConnection(configuration: configuration)
        connectionMap[configuration.database] = connection
        return connection
    }


    func switchConnectionTo(database: String) async throws {
        if let connection = connectionMap[database] {
            selectedConnection = connection
            return
        }

        if let newConfiguration = templateConnection?.copyWithDatabaseChangedTo(database: database) {
            let connection = try await initializeConnection(configuration: newConfiguration)
            selectedConnection = connection
            return
        }

        throw ConnectionManagerError.connectionNotFound(database)
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
        
        if selectedConnection === connection {
            selectedConnection = nil
        }
        
        await connection.close()
    }

    func closeAllConnections() async {
        let connections = Array(connectionMap.values)
        connectionMap.removeAll()
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

class ConnectionsManagerObservableWrapper: ObservableObject {
    let connectionManager = ConnectionsManager()
}
