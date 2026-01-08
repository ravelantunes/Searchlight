//
//  CompletionPopup.swift
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

// UI component to show completion on the edit, based on LSP completions
struct CompletionDisplayItem {
    let label: String
    let insertText: String
    let detail: String?
    let kind: CompletionItemKind?

    init(from item: CompletionItem) {
        self.label = item.label
        self.insertText = item.insertText ?? item.label
        self.detail = item.detail
        self.kind = item.kind
    }

    /// Get an icon for the completion kind
    var icon: String {
        guard let kind = kind else { return "questionmark.circle" }
        switch kind {
        case .text: return "text.alignleft"
        case .method, .function: return "function"
        case .constructor: return "hammer"
        case .field: return "rectangle.grid.1x2"
        case .variable: return "x.squareroot"
        case .class: return "cube"
        case .interface: return "square.on.square"
        case .module: return "shippingbox"
        case .property: return "list.bullet"
        case .unit: return "ruler"
        case .value: return "number"
        case .enum: return "list.number"
        case .keyword: return "textformat"
        case .snippet: return "doc.text"
        case .color: return "paintpalette"
        case .file: return "doc"
        case .reference: return "link"
        case .folder: return "folder"
        case .enumMember: return "list.bullet.indent"
        case .constant: return "c.circle"
        case .struct: return "square.stack.3d.up"
        case .event: return "bolt"
        case .operator: return "plus.slash.minus"
        case .typeParameter: return "t.circle"
        }
    }

    /// Get a color for the completion kind
    var iconColor: NSColor {
        guard let kind = kind else { return .secondaryLabelColor }
        switch kind {
        case .keyword: return .systemBlue
        case .function, .method: return .systemPurple
        case .variable, .field, .property: return .systemOrange
        case .class, .struct, .interface: return .systemGreen
        case .enum, .enumMember: return .systemYellow
        case .constant: return .systemCyan
        case .snippet: return .systemPink
        default: return .secondaryLabelColor
        }
    }
}

/// Delegate for handling completion selection
protocol CompletionPopupDelegate: AnyObject {
    func completionPopup(_ popup: CompletionPopupController, didSelectItem item: CompletionDisplayItem)
    func completionPopupDidCancel(_ popup: CompletionPopupController)
}

/// Controller for the completion popup window
class CompletionPopupController: BasePopupController {
    private var items: [CompletionDisplayItem] = []
    private var filteredItems: [CompletionDisplayItem] = []
    private var filterText: String = ""

    weak var delegate: CompletionPopupDelegate?

    /// Shows the completion popup at the given screen position
    func show(at screenPoint: NSPoint, items: [CompletionDisplayItem]) {
        self.items = items
        self.filteredItems = items
        self.filterText = ""

        // Create window if needed
        if window == nil {
            createWindow()
        }

        guard let window = window, let tableView = tableView else { return }

        // Reload data
        tableView.reloadData()

        // Select first item
        if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        // Position and size the window with modern sizing
        let rowHeight: CGFloat = 30  // Slightly taller rows for modern look
        let maxVisibleRows = 8
        let visibleRows = min(filteredItems.count, maxVisibleRows)
        let contentHeight = CGFloat(max(visibleRows, 1)) * rowHeight
        let padding: CGFloat = 8  // Padding inside glass container
        let height = contentHeight + padding * 2
        let width: CGFloat = 340

        var origin = screenPoint
        origin.y -= height  // Position below the cursor
        origin.x -= 10  // Slight offset to align with text

        window.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
        window.orderFront(nil)
    }

    /// Filter completions based on typed text
    func filter(with text: String) {
        filterText = text.lowercased()

        if filterText.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                item.label.lowercased().contains(filterText) ||
                item.insertText.lowercased().contains(filterText)
            }
        }

        tableView?.reloadData()

        if !filteredItems.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        // Hide if no matches
        if filteredItems.isEmpty {
            hide()
        }
    }

    /// Move selection up
    func selectPrevious() {
        guard let tableView = tableView else { return }
        let currentRow = tableView.selectedRow
        if currentRow > 0 {
            tableView.selectRowIndexes(IndexSet(integer: currentRow - 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(currentRow - 1)
        }
    }

    /// Move selection down
    func selectNext() {
        guard let tableView = tableView else { return }
        let currentRow = tableView.selectedRow
        if currentRow < filteredItems.count - 1 {
            tableView.selectRowIndexes(IndexSet(integer: currentRow + 1), byExtendingSelection: false)
            tableView.scrollRowToVisible(currentRow + 1)
        }
    }

    /// Confirm current selection
    func confirmSelection() {
        guard let tableView = tableView else { return }
        let selectedRow = tableView.selectedRow
        if selectedRow >= 0 && selectedRow < filteredItems.count {
            delegate?.completionPopup(self, didSelectItem: filteredItems[selectedRow])
        }
        hide()
    }

    /// Cancel completion
    override func cancel() {
        delegate?.completionPopupDidCancel(self)
        super.cancel()
    }

    private func createWindow() {
        // Create a borderless window with transparent background for glass effect
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .popUpMenu
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isOpaque = false

        // Use NSGlassEffectView for macOS 26 Liquid Glass appearance
        let glassContainer = NSGlassEffectView()
        glassContainer.cornerRadius = 10

        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Create table view with modern styling
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain

        // Create column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion"))
        column.width = 300
        tableView.addTableColumn(column)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClicked)

        scrollView.documentView = tableView

        // Set up glass container with scroll view
        glassContainer.contentView = scrollView

        window.contentView = glassContainer

        self.window = window
        self.tableView = tableView
    }

    @objc private func tableViewDoubleClicked() {
        confirmSelection()
    }
}

extension CompletionPopupController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredItems.count
    }
}

extension CompletionPopupController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredItems.count else { return nil }
        let item = filteredItems[row]

        let cellView = NSTableCellView()
        cellView.wantsLayer = true

        // Create icon with proper sizing for SF Symbols
        let imageView = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let image = NSImage(systemSymbolName: item.icon, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            imageView.image = image
            imageView.contentTintColor = item.iconColor
        }
        imageView.translatesAutoresizingMaskIntoConstraints = false

        // Create label with system font for better readability
        let textField = NSTextField(labelWithString: item.label)
        textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false

        // Create detail/type label (right-aligned, dimmed)
        let detailField = NSTextField(labelWithString: item.detail ?? "")
        detailField.font = NSFont.systemFont(ofSize: 11)
        detailField.textColor = .tertiaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail
        detailField.alignment = .right
        detailField.translatesAutoresizingMaskIntoConstraints = false

        cellView.addSubview(imageView)
        cellView.addSubview(textField)
        cellView.addSubview(detailField)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 10),
            imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: detailField.leadingAnchor, constant: -8),

            detailField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -10),
            detailField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            detailField.widthAnchor.constraint(lessThanOrEqualToConstant: 100),
        ])

        return cellView
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return CompletionRowView()
    }
}

/// Custom row view with Liquid Glass selection highlighting
class CompletionRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set { }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            // Use accent color with transparency for glass-like selection
            NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
            let selectionPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6)
            selectionPath.fill()
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        // Don't draw background - let the glass show through
    }
}
