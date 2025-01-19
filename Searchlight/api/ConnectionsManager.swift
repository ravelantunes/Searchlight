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

// This class should encapsulate the management of multiple connections (multiple window, switch schema, etc)
// TODO: refactor this, since this now is kinda redundant and confusing with PostgresConnectionManager
class ConnectionsManager {
    
    private var connectionMap: [DatabaseConnectionConfiguration: PostgresConnectionManager] = [:]
    
    func getConnectionManager(configuration: DatabaseConnectionConfiguration) -> PostgresConnectionManager {
        
        // Tries to get existing connection, if not create new one
        if let connection = connectionMap[configuration] {
            return connection
        }
        
        let connection = PostgresConnectionManager(configuration: configuration)
        connectionMap[configuration] = connection
        return connection
    }
}

class ConnectionsManagerObservableWrapper: ObservableObject {
    let connectionManager = ConnectionsManager()
}
