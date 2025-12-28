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
import AppKit

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

    // SSH Tunnel configuration
    @State private var useSSHTunnel: Bool = false
    @State private var sshHost: String = ""
    @State private var sshPort: Int? = 22
    @State private var sshUser: String = ""
    @State private var sshKeyPath: String = "~/.ssh/id_rsa"
    @State private var sshKeyPassphrase: String = ""

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

                // SSH Tunnel Section
                Section {
                    DisclosureGroup(
                        isExpanded: $useSSHTunnel,
                        content: {
                            VStack(spacing: 10) {
                                TextField("SSH Host", text: $sshHost, prompt: Text("SSH Host"))
                                    .textFieldStyle(.roundedBorder)
                                TextField("SSH Port", value: $sshPort, formatter: NumberFormatter(), prompt: Text("22"))
                                    .textFieldStyle(.roundedBorder)
                                TextField("SSH User", text: $sshUser, prompt: Text("SSH User"))
                                    .textFieldStyle(.roundedBorder)
                                HStack {
                                    TextField("SSH Key Path", text: $sshKeyPath, prompt: Text("~/.ssh/id_rsa"))
                                        .textFieldStyle(.roundedBorder)
                                    Button("Browse...") {
                                        selectSSHKeyFile()
                                    }
                                    .buttonStyle(.bordered)
                                }
                                SecureField("Key Passphrase (optional)", text: $sshKeyPassphrase, prompt: Text("Key Passphrase"))
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.top, 8)
                        },
                        label: {
                            Toggle("Use SSH Tunnel", isOn: $useSSHTunnel)
                        }
                    )
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

            // Load SSH tunnel configuration
            if let ssh = config.sshTunnel {
                self.useSSHTunnel = ssh.enabled
                self.sshHost = ssh.host
                self.sshPort = ssh.port
                self.sshUser = ssh.user
                self.sshKeyPath = ssh.keyPath
                self.sshKeyPassphrase = ssh.keyPassphrase ?? ""
            } else {
                // Reset SSH fields to defaults
                self.useSSHTunnel = false
                self.sshHost = ""
                self.sshPort = 22
                self.sshUser = ""
                self.sshKeyPath = "~/.ssh/id_rsa"
                self.sshKeyPassphrase = ""
            }
        }
    }

    private func selectSSHKeyFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select SSH Private Key File"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.sshKeyPath = url.path
            }
        }
    }
    
    private func testConnection() {
        connectionValidity = .testing
        Task {
            do {
                let connectionManager = try await connectionsManagerObservableWrapper.connectionManager.initializeConnection(configuration: stateToDatabaseConnection())
                try await connectionManager.testConnection()
                self.connectionValidity = .valid
            } catch let error as SSHTunnelError {
                self.connectionValidity = .invalid("SSH: \(error.localizedDescription)")
            } catch {
                self.connectionValidity = .invalid("DB: \(error.localizedDescription)")
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
        connectionValidity = .testing
        Task {
            do {
                let connectionManager = try await connectionsManagerObservableWrapper.connectionManager.initializeConnection(configuration: connection)
                try await connectionsManagerObservableWrapper.connectionManager.switchConnectionTo(database: database)
                try await connectionManager.testConnection()
                self.connectionValidity = .valid

                appState.selectedDatabase = database
                // We set the selection to databases here to silence SwiftUI warnings.
                // This is because we have a selectedDatabase before databases list is populated, and therefore the picker will have a selection in which is not within the possible values
                appState.databases = [database]
                appState.selectedDatabaseConnectionConfiguration = connection

                if appState.selectedDatabaseConnectionConfiguration.favorited {
                    FavoritesStore.shared.saveLastSelectedDatabaseName(databaseConnectionConfigurationName: appState.selectedDatabaseConnectionConfiguration.name)
                }
            } catch let error as SSHTunnelError {
                self.connectionValidity = .invalid("SSH: \(error.localizedDescription)")
                return
            } catch {
                self.connectionValidity = .invalid("DB: \(error.localizedDescription)")
                return
            }
        }
    }

    private func stateToDatabaseConnection(markAsFavorited: Bool = false) -> DatabaseConnectionConfiguration {
        let sshConfig: SSHTunnelConfiguration? = useSSHTunnel ? SSHTunnelConfiguration(
            enabled: true,
            host: sshHost,
            port: sshPort ?? 22,
            user: sshUser,
            keyPath: sshKeyPath,
            keyPassphrase: sshKeyPassphrase.isEmpty ? nil : sshKeyPassphrase
        ) : nil

        return DatabaseConnectionConfiguration(
            name: connectionName,
            host: host,
            port: port!,
            database: database,
            user: username,
            password: password,
            ssl: useSSL,
            favorited: markAsFavorited ? true : appState.selectedDatabaseConnectionConfiguration.favorited,
            sshTunnel: sshConfig
        )
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
