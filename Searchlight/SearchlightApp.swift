//
//  SearchlightApp.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/19/25.
//

import SwiftUI
import AppKit

@main
struct SearchlightApp: App {
    @NSApplicationDelegateAdaptor(SearchlightAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "Database Selection") {
            WindowGroupView()
                .environmentObject(appDelegate)
        }
        .windowResizability(.contentSize)
    }
}

struct WindowGroupView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appDelegate: SearchlightAppDelegate
    @ObservedObject private var appState = AppState()
    @ObservedObject private var connectionsManagerObservableWrapper = ConnectionsManagerObservableWrapper()
    @State private var databases: [String] = []
    @State private var showBanner = true
    
    // We want to open a new connection window when user closes all screens, except if they never connected to a database
    @State private var hasLeftInitialScreen = false

    var body: some View {
        NavigationSplitView() {
            if appState.selectedDatabase == nil {
                FavoriteConnectionsView(selectedConnection: $appState.selectedDatabaseConnectionConfiguration)
                    .navigationSplitViewColumnWidth(min: FormMetrics.sidebarMinWidth, ideal: FormMetrics.sidebarIdealWidth)
            } else {
                let connectionManager = connectionsManagerObservableWrapper.connectionManager
                TableSelectionContentView()
                    .environmentObject(PostgresDatabaseAPI(connectionManager: connectionManager))
                    .environmentObject(connectionsManagerObservableWrapper)
                    .environmentObject(appState)
                    .navigationSplitViewColumnWidth(min: FormMetrics.sidebarMinWidth, ideal: FormMetrics.sidebarIdealWidth)
            }
        } detail: {
            if self.appState.selectedDatabase == nil {
                VStack(spacing: 0) {
                    if showBanner {
                        CompactBannerView(showBanner: $showBanner)
                    }
                    DatabaseConnectionView()
                        .environmentObject(DatabaseConnectionConfigurationWrapper(configuration: appState.selectedDatabaseConnectionConfiguration))
                        .environmentObject(connectionsManagerObservableWrapper)
                        .environmentObject(appState)
                }
            } else {
                let connectionManager = connectionsManagerObservableWrapper.connectionManager
                DatabaseViewer()
                    .environmentObject(PostgresDatabaseAPI(connectionManager: connectionManager))
                    .environmentObject(connectionsManagerObservableWrapper)
                    .environmentObject(appState)
            }
        }
        .navigationTitle(appState.selectedDatabase == nil ? "Searchlight" : "Database: \(appState.selectedDatabase!)")
        .frame(minWidth: 700, minHeight: 500)
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar(removing: .sidebarToggle)
        .onChange(of: appState.selectedDatabase) { oldValue, newValue in
            guard newValue != nil else { return }
            hasLeftInitialScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            reopenWindowIfNeeded()
        }
    }

    private func reopenWindowIfNeeded() {
        guard !appDelegate.isTerminating else { return }
        guard hasLeftInitialScreen else { return }

        DispatchQueue.main.async {
            let hasVisibleWindows = NSApplication.shared.windows.contains { window in
                guard !(window is NSPanel) else { return false }
                return window.isVisible || window.isMiniaturized
            }

            if !hasVisibleWindows {
                openWindow(id: "Database Selection")
            }
        }
    }
}

@MainActor
final class SearchlightAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
    }
}
