//
//  DatabaseTableViewCell.swift
//  Searchlight
//
//  Created by Ravel Antunes on 5/25/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation
import AppKit
import SwiftUI

protocol DatabaseTableViewRowDelegate: AnyObject {
    func didPressTab(cell: Cell)
    func didPressBacktab(cell: Cell)
    func didCancelEditing(cell: Cell)
    func didPressEnter()
}

struct DatabaseTableViewCellAction {
    let name: String
    let systemIcon: String
    let tooltip: String
}

class DatabaseTableViewCell: NSTableRowView {
    
    static let CellIdentifier = "DatabaseTableViewCell"
    
    weak var delegate: DatabaseTableViewRowDelegate?
    var pgApi: PostgresDatabaseAPI?
    var content: Cell?
    var popover: NSPopover?
    var enabledActions: [DatabaseTableViewCellAction] = []
    
    private var popoverViewController: PopoverViewController?
    
    @IBOutlet weak var textField: NSTextField!
    @IBOutlet weak var utilityButtonsContainerView: NSView!
    @IBOutlet weak var utilityButtonsContainerViewWidthConstraint: NSLayoutConstraint!
    
    var isEditing: Bool = false {
        didSet {
            if let value = content?.value,
               [.unparseable, .unsupported].contains(value) {
                isEditing = false
            }
            textField.isEditable = isEditing
            onContentUpdate()
        }
    }
    
    static func loadFromNib() -> DatabaseTableViewCell? {
        var topLevelObjects: NSArray?
        if Bundle.main.loadNibNamed(NSNib.Name("DatabaseTableViewCell"), owner: self, topLevelObjects: &topLevelObjects) {
            (topLevelObjects?.firstObject as? DatabaseTableViewCell)?.identifier = NSUserInterfaceItemIdentifier(CellIdentifier)
            return topLevelObjects?.first(where: { $0 is DatabaseTableViewCell }) as? DatabaseTableViewCell
        }
        return nil
    }
        
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        textField.delegate = self
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            if isEditing && content?.column.position == 0 {
                window.makeFirstResponder(textField)
            }
        }
    }
    
    func showLookUpPopover() {
        guard let content else { return }
        guard popover == nil || !popover!.isShown else {
            return
        }
        
        let lookUpViewModel = LookUpViewModel(columns: [], targetTable: content.column.foreignTableName!, targetSchema: content.column.foreignSchemaName!)
        let lookupView = LookupView(lookUpViewModel: lookUpViewModel, onRowSelection: { [weak self] selectedRow in
            guard let self = self else { return }

            self.textField.stringValue = selectedRow[content.column.foreignColumnName!].value.stringRepresentation
            self.popover?.close()
            self.popover = nil
        }, onClose: { [weak self] in
            guard let self = self else { return }
            if self.popover != nil {
                self.popover!.close()
                self.popover = nil
            }
        }).environmentObject(self.pgApi!)
        
        self.popoverViewController = PopoverViewController(with: lookupView)
        popover = NSPopover()
        popover!.behavior = .applicationDefined
        popover!.contentViewController = popoverViewController
        popover!.show(relativeTo: textField.bounds, of: textField, preferredEdge: .maxX)
        
        Task {
            do {
                let columns = try await self.pgApi?.describeTable(tableName: content.column.foreignTableName!, schemaName: content.column.foreignSchemaName!)
                guard let columns = columns else { return }
                withAnimation {
                    lookUpViewModel.columns = columns
                }
            } catch {
                print("Couldn't describe table \(content.column.foreignTableName!) to show on lookup popover")
            }
        }
        
    }
    
    func onContentUpdate() {
        guard let content else { return }
        
        // Initialize action list to be populated by the different column types
        var actionList: [DatabaseTableViewCellAction] = []
        
        switch content.column.typeName {
        case "timestamp":
            // TODO: Test implementation of using a formatter on the textfield
            // textField.formatter = DateFormatter()
                        
            // Create a DateFormatter to parse the input string
            let inputFormatter = DateFormatter()
            // TODO: handle formatter for when there's timezone information
            inputFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
                    
            // Convert string to Date
            if let date = inputFormatter.date(from: content.value.stringRepresentation) {
                // Create a DateFormatter to format the output
                let outputFormatter = DateFormatter()
                outputFormatter.dateStyle = .long
                outputFormatter.timeStyle = .medium

                // Set the date to the text field
                textField.stringValue = outputFormatter.string(from: date)
            } else {
                textField.stringValue = content.value.stringRepresentation
            }
            
            if isEditing {
                actionList.append(DatabaseTableViewCellAction(name: "currentTime", systemIcon: "clock.arrow.trianglehead.counterclockwise.rotate.90", tooltip: "Current timestamp"))
            }
                        
        case "uuid":
            if isEditing && content.column.foreignColumnName == nil {
                // Only add uuid generator when editing, and it's not a foreign key (since in this case we would show the lookup popover)
                actionList.append(DatabaseTableViewCellAction(name: "uuid", systemIcon: "circle.grid.3x3.fill", tooltip: "Generates a new UUID"))
            }
            
            textField.stringValue = content.value.stringRepresentation
        default:
            textField.stringValue = content.value.stringRepresentation
        }
        
        // Add lookup popover
        if content.column.foreignColumnName != nil {
            if isEditing {
                actionList.append(DatabaseTableViewCellAction(name: "lookup", systemIcon: "magnifyingglass", tooltip: "Lookup foreign key"))
            } else {
                actionList.append(DatabaseTableViewCellAction(name: "view", systemIcon: "eye.circle", tooltip: "View the relationship"))
            }
        }
        
        textField.textColor = colorForCellValue(cellValueRepresentation: content.value)
                
        // Update the collection view
        enabledActions = actionList
        utilityButtonsContainerViewWidthConstraint.constant = calculateUtilityButtonsWidth()
        updateUtilityButtons()
        
        needsLayout = true
    }
    
    func setContent(content: Cell, editable: Bool = false) {
        self.content = content
        isEditing = editable
        onContentUpdate()
    }
    
    func colorForCellValue(cellValueRepresentation: CellValueRepresentation) -> NSColor {
        switch cellValueRepresentation {
        case .null:
            return .systemGray
        case .unparseable, .unsupported:
            return .systemRed
        default:
            return .labelColor
        }
    }
    
    private func updateUtilityButtons() {
        
        // TODO: implement view re-use for better performance
        // Reset the view.
        utilityButtonsContainerView.subviews.forEach { $0.removeFromSuperview() }
        
        var leadingAnchorView: NSView = utilityButtonsContainerView
        
        for (index, action) in enabledActions.enumerated() {
            let button = NSButton(title: action.tooltip, target: self, action: #selector(handleActionClicks(sender:)))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.identifier = NSUserInterfaceItemIdentifier(action.name)
            button.image = NSImage(systemSymbolName: action.systemIcon, accessibilityDescription: nil)
            button.toolTip = action.tooltip
            button.imagePosition = .imageOnly
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.masksToBounds = true

            utilityButtonsContainerView.addSubview(button)
            
            var leadingConstraint: NSLayoutConstraint!
            if index == 0 {
                leadingConstraint = button.leadingAnchor.constraint(equalTo: utilityButtonsContainerView.leadingAnchor, constant: 0)
            } else {
                leadingConstraint = button.leadingAnchor.constraint(equalTo: leadingAnchorView.trailingAnchor, constant: 3)
            }
                        
            // Create leading constraint between utilityButtonsContainerView and button
            NSLayoutConstraint.activate([
                leadingConstraint,
                button.widthAnchor.constraint(equalToConstant: 20),
                button.heightAnchor.constraint(equalToConstant: 20),
                button.centerYAnchor.constraint(equalTo: utilityButtonsContainerView.centerYAnchor)
            ])
            
            leadingAnchorView = button
        }
    }
    
    private func calculateUtilityButtonsWidth() -> CGFloat {
        return enabledActions.reduce(0) { result, action in
            result + 20 + 3
        }
    }
    
    @objc func handleActionClicks(sender: NSButton) {
        // TODO: make those strings an Enum
        switch sender.identifier!.rawValue {
        case "uuid":
            textField.stringValue = UUID().uuidString
        case "lookup":
            showLookUpPopover()
        case "view":
            let quickLookViewModel = QuickLookViewModel()
            let quickLookView = QuickLookView(viewModel: quickLookViewModel)
            let popoverViewController = PopoverViewController(with: quickLookView)
            popover = NSPopover()
            popover!.behavior = .transient
            popover!.contentViewController = popoverViewController
            popover!.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
            
            Task {
                do {
                    let result = try await self.pgApi?.select(params: QueryParameters(schemaName: content!.column.foreignSchemaName, tableName: content!.column.foreignTableName, filters: [
                        Filter(column: content!.column.foreignColumnName!, value: content!.value.stringRepresentation, operatorString: "equals")
                    ]))
                    withAnimation {
                        quickLookViewModel.row = result!.rows.first!
                    }                    
                } catch {
                    print("Couldn't fetch quick lookup query: \(error)")
                }
            }
        case "currentTime":
            let inputFormatter = DateFormatter()
            // TODO: handle formatter for when there's timezone information
            inputFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
            textField.stringValue = inputFormatter.string(from: Date.now)

        default :
            break
        }
    }
}

extension DatabaseTableViewCell: NSTextFieldDelegate {
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let content = content else { return false }
        
        switch commandSelector {
        case #selector(insertTab(_:)):
            delegate?.didPressTab(cell: content)
        case #selector(insertBacktab(_:)):
            delegate?.didPressBacktab(cell: content)
        case #selector(insertNewline(_:)):
            delegate?.didPressEnter()
        case #selector (cancelOperation(_:)):
            isEditing = false
            delegate?.didCancelEditing(cell: content)
        default:
            return false
        }
        return true
    }
    
    static func calculateSizeForContent(content: Cell) -> CGSize {
        let textWidth = (content.value.stringRepresentation as NSString).size().width
        let totalWidth = textWidth + 100.0
        return CGSize(width: totalWidth, height: 80)
    }
}
