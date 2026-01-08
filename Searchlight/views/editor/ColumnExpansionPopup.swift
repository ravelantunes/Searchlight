//
//  ColumnExpansionPopup.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/1/26.
//
//  Copyright (c) 2026 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import AppKit
import LanguageServerProtocol

/// Represents a column that can be selected for expansion
struct ColumnItem: Hashable {
    let name: String           // Column name (e.g., "id")
    let tableName: String?     // Table name if available (e.g., "accounts")
    let fullName: String       // Full qualified name (e.g., "accounts.id")

    var displayName: String {
        if let table = tableName {
            return "\(table).\(name)"
        }
        return name
    }

    init(name: String, tableName: String?) {
        self.name = name
        self.tableName = tableName
        if let table = tableName {
            self.fullName = "\(table).\(name)"
        } else {
            self.fullName = name
        }
    }

    init(from completionItem: CompletionItem) {
        // Parse the label to extract table and column names
        // LSP may return "table.column" or just "column"
        let label = completionItem.label
        if label.contains(".") {
            let parts = label.split(separator: ".", maxSplits: 1)
            self.tableName = String(parts[0])
            self.name = String(parts[1])
            self.fullName = label
        } else {
            self.name = label
            // Try to get table from detail
            self.tableName = completionItem.detail
            if let table = self.tableName {
                self.fullName = "\(table).\(name)"
            } else {
                self.fullName = name
            }
        }
    }
}

/// Delegate for handling column expansion selection
protocol ColumnExpansionDelegate: AnyObject {
    func columnExpansion(_ popup: ColumnExpansionPopupController, didSelectColumns columns: [ColumnItem], keepStar: Bool)
    func columnExpansionDidCancel(_ popup: ColumnExpansionPopupController)
}

/// Controller for the column expansion popup with drag-selection support
class ColumnExpansionPopupController: BasePopupController {
    private var keepStarCheckbox: NSButton?
    private var applyButton: NSButton?

    private var columns: [ColumnItem] = []
    private var selectedColumns: Set<ColumnItem> = []
    private var isDragging = false
    private var dragStartRow: Int = -1

    weak var delegate: ColumnExpansionDelegate?

    /// Shows the column expansion popup at the given screen position
    func show(at screenPoint: NSPoint, columns: [ColumnItem]) {
        self.columns = columns
        self.selectedColumns = []
        self.isDragging = false
        self.dragStartRow = -1

        // Create window if needed
        if window == nil {
            createWindow()
        }

        guard let window = window, let tableView = tableView else { return }

        // Reload data
        tableView.reloadData()

        // Reset checkbox
        keepStarCheckbox?.state = .off

        // Position and size the window
        let rowHeight: CGFloat = 26
        let maxVisibleRows = 12
        let visibleRows = min(columns.count, maxVisibleRows)
        let contentHeight = CGFloat(max(visibleRows, 1)) * rowHeight
        let headerHeight: CGFloat = 36  // For "Keep *" checkbox
        let footerHeight: CGFloat = 44  // For Apply button
        let padding: CGFloat = 8
        let height = contentHeight + headerHeight + footerHeight + padding * 2
        let width: CGFloat = 280

        var origin = screenPoint
        origin.y -= height  // Position below the cursor
        origin.x -= 10

        // Ensure window stays on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            if origin.x + width > screenFrame.maxX {
                origin.x = screenFrame.maxX - width - 10
            }
            if origin.y < screenFrame.minY {
                origin.y = screenFrame.minY + 10
            }
        }

        let finalFrame = NSRect(x: origin.x, y: origin.y, width: width, height: height)

        // Start with a small bubble at the click point, then animate to full size
        let startScale: CGFloat = 0.3
        let startWidth = width * startScale
        let startHeight = height * startScale
        let startX = screenPoint.x - startWidth / 2
        let startY = screenPoint.y - startHeight / 2
        let startFrame = NSRect(x: startX, y: startY, width: startWidth, height: startHeight)

        // Set initial state: small and transparent
        window.setFrame(startFrame, display: false)
        window.alphaValue = 0
        window.orderFront(nil)

        // Animate to final state with spring-like bubble effect
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1) // Slight overshoot
            context.allowsImplicitAnimation = true

            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1
        }
    }

    /// Hides the popup with animation
    override func hide() {
        guard let window = window, window.isVisible else { return }

        let currentFrame = window.frame
        let endScale: CGFloat = 0.3
        let endWidth = currentFrame.width * endScale
        let endHeight = currentFrame.height * endScale
        let endX = currentFrame.midX - endWidth / 2
        let endY = currentFrame.midY - endHeight / 2
        let endFrame = NSRect(x: endX, y: endY, width: endWidth, height: endHeight)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true

            window.animator().setFrame(endFrame, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1  // Reset for next show
        })
    }

    /// Cancel and close
    override func cancel() {
        delegate?.columnExpansionDidCancel(self)
        super.cancel()
    }

    /// Apply current selection
    func apply() {
        let keepStar = keepStarCheckbox?.state == .on
        let selectedArray = columns.filter { selectedColumns.contains($0) }
        delegate?.columnExpansion(self, didSelectColumns: selectedArray, keepStar: keepStar)
        hide()
    }

    private func createWindow() {
        // Create borderless panel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false

        // Glass container
        let glassContainer = NSGlassEffectView()
        glassContainer.cornerRadius = 10

        // Main stack view
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        // Header with "Keep *" checkbox
        let headerView = NSStackView()
        headerView.orientation = .horizontal
        headerView.translatesAutoresizingMaskIntoConstraints = false

        let keepStarCheckbox = NSButton(checkboxWithTitle: "Keep *", target: self, action: nil)
        keepStarCheckbox.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        self.keepStarCheckbox = keepStarCheckbox

        let titleLabel = NSTextField(labelWithString: "Select columns")
        titleLabel.font = NSFont.systemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor

        headerView.addArrangedSubview(keepStarCheckbox)
        headerView.addArrangedSubview(NSView()) // Spacer
        headerView.addArrangedSubview(titleLabel)

        // Scroll view with table
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Table view for columns
        let tableView = ColumnTableView()
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.selectionHighlightStyle = .none  // We handle selection ourselves
        tableView.style = .plain
        tableView.allowsMultipleSelection = true
        tableView.columnController = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column"))
        column.width = 260
        tableView.addTableColumn(column)

        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        self.tableView = tableView

        // Footer with Apply button
        let footerView = NSStackView()
        footerView.orientation = .horizontal
        footerView.translatesAutoresizingMaskIntoConstraints = false

        let applyButton = NSButton(title: "Apply", target: self, action: #selector(applyClicked))
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"  // Enter key
        self.applyButton = applyButton

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"  // Escape key

        footerView.addArrangedSubview(NSView()) // Spacer
        footerView.addArrangedSubview(cancelButton)
        footerView.addArrangedSubview(applyButton)

        // Assemble stack
        stackView.addArrangedSubview(headerView)
        stackView.addArrangedSubview(scrollView)
        stackView.addArrangedSubview(footerView)

        // Constraints
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            scrollView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            footerView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
        ])

        glassContainer.contentView = stackView
        panel.contentView = glassContainer

        self.window = panel
    }

    @objc private func applyClicked() {
        apply()
    }

    @objc private func cancelClicked() {
        cancel()
    }

    // MARK: - Drag Selection

    func handleMouseDown(at row: Int) {
        guard row >= 0 && row < columns.count else { return }
        isDragging = true
        dragStartRow = row

        // Toggle the clicked row
        let column = columns[row]
        if selectedColumns.contains(column) {
            selectedColumns.remove(column)
        } else {
            selectedColumns.insert(column)
        }
        tableView?.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }

    func handleMouseDragged(to row: Int) {
        guard isDragging, row >= 0 && row < columns.count else { return }

        // Select all rows between dragStartRow and current row
        let minRow = min(dragStartRow, row)
        let maxRow = max(dragStartRow, row)

        for r in minRow...maxRow {
            let column = columns[r]
            selectedColumns.insert(column)
        }

        tableView?.reloadData(forRowIndexes: IndexSet(integersIn: minRow...maxRow), columnIndexes: IndexSet(integer: 0))
    }

    func handleMouseUp() {
        isDragging = false
        dragStartRow = -1
    }

    func isColumnSelected(_ column: ColumnItem) -> Bool {
        return selectedColumns.contains(column)
    }
}

// MARK: - NSTableViewDataSource

extension ColumnExpansionPopupController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return columns.count
    }
}

// MARK: - NSTableViewDelegate

extension ColumnExpansionPopupController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < columns.count else { return nil }
        let column = columns[row]
        let isSelected = selectedColumns.contains(column)

        let cellView = NSView()
        cellView.wantsLayer = true

        // Checkbox indicator
        let checkbox = NSImageView()
        let imageName = isSelected ? "checkmark.circle.fill" : "circle"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            checkbox.image = image
            checkbox.contentTintColor = isSelected ? .controlAccentColor : .tertiaryLabelColor
        }
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        // Column name
        let nameField = NSTextField(labelWithString: column.displayName)
        nameField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        nameField.textColor = isSelected ? .labelColor : .secondaryLabelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false

        cellView.addSubview(checkbox)
        cellView.addSubview(nameField)

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
            checkbox.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 18),
            checkbox.heightAnchor.constraint(equalToConstant: 18),

            nameField.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            nameField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            nameField.trailingAnchor.constraint(lessThanOrEqualTo: cellView.trailingAnchor, constant: -8),
        ])

        // Selection background
        if isSelected {
            cellView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            cellView.layer?.cornerRadius = 4
        }

        return cellView
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return ColumnRowView()
    }
}

/// Custom row view for column selection
class ColumnRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        // Don't draw default selection - we handle it in cell view
    }

    override func drawBackground(in dirtyRect: NSRect) {
        // Transparent background
    }
}

/// Custom table view that handles drag selection
class ColumnTableView: NSTableView {
    weak var columnController: ColumnExpansionPopupController?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        columnController?.handleMouseDown(at: row)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        columnController?.handleMouseDragged(to: row)
    }

    override func mouseUp(with event: NSEvent) {
        columnController?.handleMouseUp()
    }
}
