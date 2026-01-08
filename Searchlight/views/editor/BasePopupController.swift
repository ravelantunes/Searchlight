//
//  BasePopupController.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/7/26.
//
//  Copyright (c) 2026 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import AppKit

/// Base class for popup controllers that provides common window management,
/// visibility tracking, and automatic dismissal when the app loses focus.
class BasePopupController: NSObject {

    // MARK: - Properties

    /// The popup window. Subclasses should set this in their createWindow() method.
    internal var window: NSWindow?

    /// The main table view for the popup.
    internal var tableView: NSTableView?

    /// Observer token for app resignation notification
    private var resignObserver: NSObjectProtocol?

    // MARK: - Computed Properties

    /// Returns true if the popup window is currently visible
    var isVisible: Bool {
        return window?.isVisible ?? false
    }

    // MARK: - Initialization

    override init() {
        super.init()
        setupNotificationObservers()
    }

    deinit {
        teardownNotificationObservers()
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidResignActive()
        }
    }

    private func teardownNotificationObservers() {
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
            resignObserver = nil
        }
    }

    /// Called when the app loses focus. Default implementation hides the popup.
    /// Subclasses can override to customize behavior.
    func handleAppDidResignActive() {
        if isVisible {
            hide()
        }
    }

    // MARK: - Public Methods

    /// Hides the popup window. Subclasses can override for custom animations.
    func hide() {
        window?.orderOut(nil)
    }

    /// Called to cancel the popup. Subclasses should override to notify their
    /// delegate before calling super.cancel().
    func cancel() {
        hide()
    }
}
