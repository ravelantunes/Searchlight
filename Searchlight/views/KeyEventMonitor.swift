//
//  KeyEventMonitor.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/2/25.
//
//  Copyright (c) 2025 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//
import SwiftUI
import AppKit

// Observable object to handle registering and de-registering of NSEvent, so it can be used in SwiftUI without circular references.
class KeyEventMonitor: ObservableObject {
    private var monitor: Any?
    
    func startMonitoring(escapeKey: (() -> Void)? = nil, commandEnter: (() -> Void)? = nil) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape key (keyCode 53)
            if event.keyCode == 53, let escapeKey = escapeKey {
                escapeKey()
                return nil
            }

            // Command+Enter (keyCode 36 for Return, 76 for Enter on numpad)
            if event.modifierFlags.contains(.command),
               (event.keyCode == 36 || event.keyCode == 76),
               let commandEnter = commandEnter {
                commandEnter()
                return nil
            }

            return event
        }
    }

    func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
