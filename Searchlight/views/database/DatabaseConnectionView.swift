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

struct DatabaseConnectionView: View {
    @State private var connectionName: String = ""
    @State private var host: String = ""
    @State private var port: Int? = 5432
    @State private var database: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var useSSL: Bool = true

    // SSH Tunnel configuration
    @State private var useSSHTunnel: Bool = false
    @State private var sshHost: String = ""
    @State private var sshPort: Int? = 22
    @State private var sshUser: String = ""
    @State private var sshKeyPath: String = "~/.ssh/id_rsa"
    @State private var sshKeyBookmarkData: Data? = nil

    // Visual customization
    @State private var selectedColorHex: String? = nil

    @State private var connectionValidity: ConnectionValidityState = .untested

    @StateObject private var keyEventMonitor = KeyEventMonitor()

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var connectionsManagerObservableWrapper: ConnectionsManagerObservableWrapper
    @EnvironmentObject var selectedConnection: DatabaseConnectionConfigurationWrapper

    private var isEditingExistingFavorite: Bool {
        guard !connectionName.isEmpty else { return false }
        return FavoritesStore.shared.favorites.contains(where: { $0.name == connectionName })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                // Connection Section
                GroupedSectionView(title: "Connection") {
                    ConnectionSection(
                        host: $host,
                        port: $port,
                        database: $database,
                        username: $username,
                        password: $password,
                        useSSL: $useSSL
                    )
                }

                // SSH Tunnel Section
                GroupedSectionView(title: "SSH Tunnel") {
                    SSHTunnelSection(
                        useSSHTunnel: $useSSHTunnel,
                        sshHost: $sshHost,
                        sshPort: $sshPort,
                        sshUser: $sshUser,
                        sshKeyPath: $sshKeyPath,
                        sshKeyBookmarkData: $sshKeyBookmarkData
                    )
                }

                // Appearance Section (for saving favorites)
                GroupedSectionView(title: "Save as Favorite") {
                    FormTextField(label: "Name", text: $connectionName, placeholder: "My Database", showDivider: true)
                    ColorPickerRow(selectedColorHex: $selectedColorHex)
                }

                // Status display (only show when relevant)
                if case .untested = connectionValidity {
                    // Don't show anything
                } else {
                    ConnectionStatusView(state: connectionValidity)
                }

                // Action Buttons
                actionButtons
            }
            .padding(Spacing.xl)
            .frame(maxWidth: FormMetrics.maxFormWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selectedConnection) {
            updateStateFromSelectedConnection()
            connectionValidity = .untested

            if selectedConnection.configuration?.connectRightAway == true {
                connect()
            }
        }
        .onAppear {
            keyEventMonitor.startMonitoring(
                commandEnter: {
                    if validateForm() {
                        connect()
                    }
                }
            )
        }
        .onDisappear {
            keyEventMonitor.stopMonitoring()
        }
    }

    private var actionButtons: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Button {
                    testConnection()
                } label: {
                    Text("Test Connection")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    connect()
                } label: {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
            }

            Button {
                addToFavorites()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: isEditingExistingFavorite ? "checkmark" : "star")
                    Text(isEditingExistingFavorite ? "Update Favorite" : "Save to Favorites")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(connectionName.isEmpty)

            Text("Press \u{2318}\u{21A9} to connect quickly")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, Spacing.xs)
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

            // Load color customization
            self.selectedColorHex = config.favoriteColor

            // Load SSH tunnel configuration
            if let ssh = config.sshTunnel {
                self.useSSHTunnel = ssh.enabled
                self.sshHost = ssh.host
                self.sshPort = ssh.port
                self.sshUser = ssh.user
                self.sshKeyPath = ssh.keyPath
                self.sshKeyBookmarkData = ssh.keyBookmarkData
                if let bookmarkData = ssh.keyBookmarkData {
                    print("Loaded bookmark data for SSH key: \(bookmarkData.count) bytes")
                } else {
                    print("No bookmark data found in saved config")
                }
            } else {
                // Reset SSH fields to defaults
                self.useSSHTunnel = false
                self.sshHost = ""
                self.sshPort = 22
                self.sshUser = ""
                self.sshKeyPath = "~/.ssh/id_rsa"
                self.sshKeyBookmarkData = nil
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
            self.connectionValidity = .invalid("Missing connection info")
            return
        }

        let config = stateToDatabaseConnection(markAsFavorited: true)
        FavoritesStore.shared.saveFavorite(databaseConnectionConfiguration: config)
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
                appState.databases = [database]
                appState.selectedDatabaseConnectionConfiguration = connection

                if appState.selectedDatabaseConnectionConfiguration.favorited {
                    FavoritesStore.shared.saveLastSelectedDatabaseName(databaseConnectionConfigurationName: appState.selectedDatabaseConnectionConfiguration.name)
                }

                // Start the Language Server for SQL editor features
                let tunnelPort = connectionsManagerObservableWrapper.connectionManager.tunnelLocalPort
                Task {
                    do {
                        try await connectionsManagerObservableWrapper.connectionManager.lspManager.start(config: connection, tunnelPort: tunnelPort)
                    } catch {
                        // LSP failure is non-fatal - editor still works without it
                        print("[LSP] Failed to start language server: \(error)")
                    }
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
            keyBookmarkData: sshKeyBookmarkData
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
            sshTunnel: sshConfig,
            favoriteColor: selectedColorHex,
            favoriteIcon: "star.fill"
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
        return !host.isEmpty && !database.isEmpty && !username.isEmpty
    }
}

#Preview {
    DatabaseConnectionView()
}
