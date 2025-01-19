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
    
    func startMonitoring(escapeKey: @escaping () -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape key
                escapeKey()
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
