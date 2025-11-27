//
//  DatabaseConnectionView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 6/24/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation
import SwiftUI
import PostgresKit

enum ConnectionValidityState {
    case untested
    case testing
    case valid
    case invalid(String)
}

struct DatabaseConnectionView: View {
    @State private var connectionName: String = ""
    @State private var host: String = ""
    @State private var port: Int? = 5432
    @State private var database: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var useSSL: Bool = true
    @State private var showBanner = true

    @State private var connectionValidity: ConnectionValidityState = .untested
    
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var connectionsManagerObservableWrapper: ConnectionsManagerObservableWrapper
    @EnvironmentObject var selectedConnection: DatabaseConnectionConfigurationWrapper

    var body: some View {
        ZStack(alignment: .bottom) {
            Form {
                Section(header: Text("Connection Details").font(.title2).padding(8)) {
                    // TODO: review SwiftUI method to apply textFieldStyle automatically
                    TextField("Connection Name", text: $connectionName, prompt: Text("Connection Name"))
                        .textFieldStyle(.roundedBorder)
                    TextField("Host", text: $host, prompt: Text("Host"))
                        .textFieldStyle(.roundedBorder)
                    TextField("Port", value: $port, formatter: NumberFormatter(), prompt: Text("Port"))
                        .textFieldStyle(.roundedBorder)
                    TextField("Database", text: $database, prompt: Text("Database"))
                        .textFieldStyle(.roundedBorder)
                    TextField("Username", text: $username, prompt: Text("Username"))
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password, prompt: Text("Password"))
                        .textFieldStyle(.roundedBorder)
                }
                Section {
                    VStack(spacing: 15) {
                        HStack {
                            Toggle("Use SSL", isOn: $useSSL)
                            Spacer()
                            Button("Test Connection") {
                                testConnection()
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }
                        
                        Button(action: connect) {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(action: addToFavorites) {
                            Text("Add to Favorites")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Text(connectionValidityText())
                            .foregroundColor(connectionValidityTextColor())
                            .textSelection(.enabled)
                            .font(.subheadline)
                            .frame(height: 80, alignment: .top)
                    }
                }
            }
            .frame(maxWidth: 400)
            .onChange(of: selectedConnection, {
                updateStateFromSelectedConnection()
                connectionValidity = .untested
                
                if selectedConnection.configuration!.connectRightAway {
                    connect()
                }
            })
            .animation(.easeInOut, value: showBanner)
        }        
    }
    
    private func connectionValidityText() -> String {
        switch connectionValidity {
        case .untested: return ""
        case .testing: return "Testing connection..."
        case .valid: return "Connection is valid"
        case .invalid(let message): return message
        }
    }
    
    private func connectionValidityTextColor() -> Color {
        switch connectionValidity {
        case .untested: return .primary
        case .testing: return .primary
        case .valid: return .green
        case .invalid: return .red
        }
    }
    
    private func updateStateFromSelectedConnection() {
        if let config = selectedConnection.configuration {
            self.connectionName = config.name
            self.host = config.host
            self.port = config.port
            self.database = config.database
            self.username = config.user
            self.password = config.password
            self.useSSL = config.ssl
        }
    }
    
    private func testConnection() {
        let connectionManager = connectionsManagerObservableWrapper.connectionManager.initializeConnection(configuration: stateToDatabaseConnection())
        
        connectionValidity = .testing
        Task {
            do {
                try await connectionManager.testConnection()
                self.connectionValidity = .valid
            } catch {
                self.connectionValidity = .invalid("Can't connect to database: \(error.localizedDescription)")
            }
        }
    }
    
    private func addToFavorites() {
        guard validateForm() && connectionName != "" else {
            // TODO: provide information on missing fields
            self.connectionValidity = .invalid("Missing connection info")
            return
        }
        
        FavoritesStore.shared.saveFavorite(databaseConnectionConfiguration: stateToDatabaseConnection(markAsFavorited: true))
    }
    
    private func connect() {
        let connection = stateToDatabaseConnection()
        let connectionManager = connectionsManagerObservableWrapper.connectionManager.initializeConnection(configuration: connection)
        try! connectionsManagerObservableWrapper.connectionManager.switchConnectionTo(database: database)
        connectionValidity = .testing
        Task {
            do {
                try await connectionManager.testConnection()
                self.connectionValidity = .valid
            } catch {
                self.connectionValidity = .invalid("Can't connect to database: \(error.localizedDescription)")
                return
            }
            
            appState.selectedDatabase = database
            // We set the selection to databases here to silence SwiftUI warnings.
            // This is because we have a selectedDatabase before databases list is populated, and therefore the picker will have a selection in which is not within the possible values
            appState.databases = [database]
            appState.selectedDatabaseConnectionConfiguration = connection
         
            if appState.selectedDatabaseConnectionConfiguration.favorited {
                FavoritesStore.shared.saveLastSelectedDatabaseName(databaseConnectionConfigurationName: appState.selectedDatabaseConnectionConfiguration.name)
            }
        }
        
    }

    private func stateToDatabaseConnection(markAsFavorited: Bool = false) -> DatabaseConnectionConfiguration {
        return DatabaseConnectionConfiguration(name: connectionName, host: host, port: port!, database: database, user: username, password: password, ssl: useSSL, favorited: markAsFavorited ? true : appState.selectedDatabaseConnectionConfiguration.favorited)
    }
    
    private func stateToConfig() -> SQLPostgresConfiguration {
        let context = try! NIOSSLContext(configuration: TLSConfiguration.makeClientConfiguration())
        
        return SQLPostgresConfiguration(
            hostname: self.host,
            port: self.port ?? 5432,
            username: self.username,
            password: self.password,
            database: self.database,
            tls: self.useSSL ? .require(context) : .disable
        )
    }
    
    private func validateForm() -> Bool {
        // TODO: refactor this to provide information on missing fields
        return !host.isEmpty && !database.isEmpty && !username.isEmpty
    }
}

#Preview {
    DatabaseConnectionView()
}
