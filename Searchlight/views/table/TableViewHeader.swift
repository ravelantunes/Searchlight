//
//  TableViewHeader.swift
//  Searchlight
//
//  Created by Ravel Antunes on 12/23/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//
import AppKit

class TableHeaderView: NSTableHeaderView {
    var popover: NSPopover?
    var trackingArea: NSTrackingArea?
    var data: SelectResult = SelectResult(columns: [], rows: [])    
    var popoverShowingAtColumnIndex: Int = -1
    
    // Timer to keep track of mouse over
    var popoverTimer: Timer?
    var currentColumnBeingMousedOver: Int = -1
    let timeToShowPopover: TimeInterval = 0.5

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingTrackingArea = trackingArea {
            self.removeTrackingArea(existingTrackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect,. mouseMoved]
        trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        if let trackingArea = trackingArea {
            self.addTrackingArea(trackingArea)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let mouseOverColumnIndex = column(at: self.convert(event.locationInWindow, from: nil))
        
        // If popover is showing but mouse over changed, close popover
        if popover != nil && mouseOverColumnIndex != popoverShowingAtColumnIndex {
            closePopover()
        }
        
        if mouseOverColumnIndex != currentColumnBeingMousedOver {
            popoverTimer?.invalidate()
            popoverTimer = Timer.scheduledTimer(withTimeInterval: timeToShowPopover, repeats: false) { [weak self] timer in
                guard let self = self else {
                    return
                }
                let rect = self.headerRect(ofColumn: mouseOverColumnIndex)
                self.popoverShowingAtColumnIndex = mouseOverColumnIndex
                self.showPopover(at: rect)
            }
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // TODO: need to move the logic of closing popover to checking when mouse exited popover, in order to enable the user to interact with the popover without it closing
        popoverTimer?.invalidate()
        popoverShowingAtColumnIndex = -1
        closePopover()
    }

    private func showPopover(at rect: NSRect) {
        guard popover == nil else { return }
        
        let column = data.columns[popoverShowingAtColumnIndex]
        let columnName = column.name
                
        // TODO: abstract statistics somewhere else. They are here just as a proof-of-concept for now
        // Calculate the number of unique values in data.column
        var uniqueValuesSet = Set<String>()
        var nullValuesCount = 0
        
        var valueCounts: [String?: Int] = [:]
        
        data.rows.forEach { row in
            let value = row.cells[popoverShowingAtColumnIndex].value
            valueCounts[value.stringRepresentation, default: 0] += 1
            
            if value == .null {
                nullValuesCount += 1
            } else {
                uniqueValuesSet.insert(value.stringRepresentation)
            }                        
        }
        
        let statistics = ColumnStatistics(tableName: columnName, valueCounts: valueCounts, uniqueValuesCount: uniqueValuesSet.count, nullValuesCount: nullValuesCount)
            
        let viewController = ColumnStatisticsViewController(columnStatistics: statistics)
        popover = NSPopover()
        popover?.contentViewController = viewController
        popover?.behavior = .transient
        popover?.show(relativeTo: rect, of: self, preferredEdge: .maxY)
    }

    private func closePopover() {
        popover?.close()
        popover = nil
    }
}
