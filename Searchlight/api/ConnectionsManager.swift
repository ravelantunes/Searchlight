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
    
    func initializeConnection(configuration: DatabaseConnectionConfiguration) async throws -> PostgresConnection {
        if templateConnection == nil {
            templateConnection = configuration
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
        }
    }
    
    func connection(database: String) throws -> PostgresConnection {                 
        guard let connection = connectionMap[database] else {
            // TODO: throw error
            throw ConnectionManagerError.connectionNotFound(database)
        }
        return connection
    }
}

class ConnectionsManagerObservableWrapper: ObservableObject {
    let connectionManager = ConnectionsManager()
}
