//
//  SearchlightApp.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/19/25.
//

import SwiftUI

@main
struct SearchlightApp: App {
    var body: some Scene {
        WindowGroup(id: "Database Selection") {
            WindowGroupView()
        }
        .windowResizability(.contentSize)
    }
}

struct WindowGroupView: View {
    @ObservedObject private var appState = AppState()
    @ObservedObject private var connectionsManagerObservableWrapper = ConnectionsManagerObservableWrapper()
    @State private var databases: [String] = []
    @State private var showBanner = true

    var body: some View {
        NavigationSplitView() {
            if appState.selectedDatabase == nil {
                FavoriteConnectionsView(selectedConnection: $appState.selectedDatabaseConnectionConfiguration)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 200)
                if showBanner {
                    BannerView(showBanner: $showBanner)
                }
            } else {
                let connectionManager = connectionsManagerObservableWrapper.connectionManager
                TableSelectionContentView()
                    .environmentObject(PostgresDatabaseAPI(connectionManager: connectionManager))
                    .environmentObject(connectionsManagerObservableWrapper)
                    .environmentObject(appState)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 200)
            }         
        } detail: {
            if self.appState.selectedDatabase == nil {
                DatabaseConnectionView()
                    .environmentObject(DatabaseConnectionConfigurationWrapper(configuration: appState.selectedDatabaseConnectionConfiguration))
                    .environmentObject(connectionsManagerObservableWrapper)
                    .environmentObject(appState)
            } else {
                let connectionManager = connectionsManagerObservableWrapper.connectionManager
                DatabaseViewer()
                    .environmentObject(PostgresDatabaseAPI(connectionManager: connectionManager))
                    .environmentObject(connectionsManagerObservableWrapper)
                    .environmentObject(appState)
            }
        }
        .navigationTitle(appState.selectedDatabase == nil ? "Searchlight" : "Database: \(appState.selectedDatabase!)")
        .frame(minWidth: 600, minHeight: 450)
        .navigationSplitViewStyle(.prominentDetail)
        .onChange(of: appState.selectedDatabase, initial: true) { oldValue, newValue in            
            guard let newValue else { return }
            try? connectionsManagerObservableWrapper.connectionManager.switchConnectionTo(database: newValue)
        }
    }
}
