//
//  AppKitTextView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 11/10/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI
import AppKit
import SQLParser
import LanguageServerProtocol
import Combine

struct AppKitTextView: NSViewRepresentable {
    @Binding var text: String
    var onQuerySubmit: ((String) -> Void)?
    var lspManager: PostgresLSPManager?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let textView = TextViewWithSubmit()
        textView.isEditable = true
        textView.isSelectable = true
        textView.string = text
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.lspManager = lspManager
        textView.onSubmit = { text in
            guard let onQuerySubmit = onQuerySubmit else { return }
            onQuerySubmit(text)
        }

        // Wrap the textView in an NSScrollView.
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizesSubviews = true

        // Initial syntax highlighting
        updateSyntaxHighlighting(in: textView)

        // Set up LSP document if manager is available
        if let lspManager = lspManager {
            context.coordinator.setupLSP(textView: textView, lspManager: lspManager)
        }

        // Make sure the textView resizes with the scroll view.
        textView.autoresizingMask = [.width]
        return scrollView

     }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? TextViewWithSubmit {
            if textView.string != text {
                textView.string = text
                updateSyntaxHighlighting(in: textView)
            }

            // Update LSP manager reference
            textView.lspManager = lspManager

            // Apply diagnostics if available
            if let lspManager = lspManager {
                context.coordinator.applyDiagnostics(textView: textView, diagnostics: lspManager.diagnostics)
            }
        }
    }

    /// Uses your tokenize() function to apply syntax highlighting to the text in the NSTextView.
    private func updateSyntaxHighlighting(in textView: NSTextView) {
        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        // Reset text attributes
        textView.textStorage?.setAttributes([.foregroundColor: NSColor.labelColor,
                                              .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)],
                                             range: fullRange)
        
        // Tokenize the text; tokens now include an NSRange.
        let tokens = tokenize(textView.string)
        
        for token in tokens {
            switch token {
            case .keyword(_, let range):
                textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
            case .string(_, let range):
                textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.systemRed, range: range)
            case .number(_, let range):
                textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: range)
            case .identifier(_, let range):
                textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: range)
            default:
                break
            }
        }

        // Underline * characters in SELECT context to indicate they're clickable
        highlightSelectStars(in: textView)
    }

    /// Finds and underlines * characters that are in SELECT context (clickable for column expansion)
    private func highlightSelectStars(in textView: NSTextView) {
        let text = textView.string
        let nsText = text as NSString

        // Find all * characters
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let starRange = nsText.range(of: "*", options: [], range: searchRange)
            if starRange.location == NSNotFound {
                break
            }

            // Check if this * is in a SELECT context
            if isStarInSelectContext(at: starRange.location, in: text) {
                // Apply link-like styling: underline + accent color
                textView.textStorage?.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.controlAccentColor,
                    .foregroundColor: NSColor.controlAccentColor,
                    .cursor: NSCursor.pointingHand
                ], range: starRange)
            }

            // Move search range forward
            searchRange.location = starRange.location + 1
            searchRange.length = nsText.length - searchRange.location
        }
    }

    /// Check if the * at the given position is in a SELECT context (not multiplication)
    private func isStarInSelectContext(at position: Int, in text: String) -> Bool {
        let lowerText = text.lowercased()
        let nsText = lowerText as NSString

        // Look backwards from position to find SELECT keyword
        let beforeStar = nsText.substring(to: position)

        // Find the last SELECT before this position
        guard let selectRange = beforeStar.range(of: "select", options: .backwards) else {
            return false
        }

        // Check there's no FROM between SELECT and *
        let afterSelect = String(beforeStar[selectRange.upperBound...])
        if afterSelect.contains("from") {
            return false
        }

        return true
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AppKitTextView
        private var updateTask: Task<Void, Never>?
        private var cancellables = Set<AnyCancellable>()
        private var hasOpenedDocument = false

        init(_ parent: AppKitTextView) {
            self.parent = parent
        }

        @MainActor
        func setupLSP(textView: TextViewWithSubmit, lspManager: PostgresLSPManager) {
            // Open document in LSP when first set up
            Task { @MainActor in
                guard lspManager.state == .connected else { return }
                do {
                    try await lspManager.openDocument(text: textView.string)
                    self.hasOpenedDocument = true
                } catch {
                    print("[LSP] Failed to open document: \(error)")
                }
            }

            // Subscribe to diagnostics changes
            lspManager.$diagnostics
                .receive(on: DispatchQueue.main)
                .sink { [weak self] diagnostics in
                    self?.applyDiagnostics(textView: textView, diagnostics: diagnostics)
                }
                .store(in: &cancellables)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.updateSyntaxHighlighting(in: textView)

            // Debounced LSP update
            updateTask?.cancel()
            updateTask = Task { @MainActor in
                // Debounce: wait 300ms before sending update
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }

                if let lspManager = parent.lspManager, lspManager.state == .connected {
                    do {
                        if !hasOpenedDocument {
                            try await lspManager.openDocument(text: textView.string)
                            hasOpenedDocument = true
                        } else {
                            try await lspManager.updateDocument(text: textView.string)
                        }
                    } catch {
                        print("[LSP] Failed to update document: \(error)")
                    }
                }
            }
        }

        /// Apply diagnostic underlines from LSP
        func applyDiagnostics(textView: NSTextView, diagnostics: [Diagnostic]) {
            guard let textStorage = textView.textStorage else { return }
            let text = textView.string

            // First, remove existing diagnostic underlines
            let fullRange = NSRange(location: 0, length: text.utf16.count)
            textStorage.removeAttribute(.underlineStyle, range: fullRange)
            textStorage.removeAttribute(.underlineColor, range: fullRange)
            textStorage.removeAttribute(.toolTip, range: fullRange)

            // Apply new diagnostics
            for diagnostic in diagnostics {
                guard let nsRange = convertLSPRangeToNSRange(diagnostic.range, in: text) else {
                    continue
                }

                // Choose color based on severity
                let underlineColor: NSColor
                switch diagnostic.severity {
                case .error:
                    underlineColor = .systemRed
                case .warning:
                    underlineColor = .systemYellow
                case .information:
                    underlineColor = .systemBlue
                case .hint:
                    underlineColor = .systemGray
                case .none:
                    underlineColor = .systemRed
                }

                // Apply underline
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                textStorage.addAttribute(.underlineColor, value: underlineColor, range: nsRange)
                textStorage.addAttribute(.toolTip, value: diagnostic.message, range: nsRange)
            }
        }

        /// Convert LSP Position (line, character) to NSRange
        private func convertLSPRangeToNSRange(_ range: LSPRange, in text: String) -> NSRange? {
            let lines = text.components(separatedBy: "\n")

            var startOffset = 0
            for i in 0..<range.start.line {
                guard i < lines.count else { return nil }
                startOffset += lines[i].utf16.count + 1 // +1 for newline
            }
            startOffset += range.start.character

            var endOffset = 0
            for i in 0..<range.end.line {
                guard i < lines.count else { return nil }
                endOffset += lines[i].utf16.count + 1
            }
            endOffset += range.end.character

            let length = endOffset - startOffset
            guard startOffset >= 0, length >= 0, startOffset + length <= text.utf16.count else {
                return nil
            }

            return NSRange(location: startOffset, length: max(1, length))
        }
    }
}

class TextViewWithSubmit: NSTextView, CompletionPopupDelegate, ColumnExpansionDelegate {

    // onSubmit Reference
    var onSubmit: ((String) -> Void)?

    // LSP manager for completions
    weak var lspManager: PostgresLSPManager?

    // Completion popup
    private lazy var completionPopup: CompletionPopupController = {
        let popup = CompletionPopupController()
        popup.delegate = self
        return popup
    }()

    // Column expansion popup
    private lazy var columnExpansionPopup: ColumnExpansionPopupController = {
        let popup = ColumnExpansionPopupController()
        popup.delegate = self
        return popup
    }()

    // Track the range where completion started (for replacing text)
    private var completionStartLocation: Int = 0
    private var completionTask: Task<Void, Never>?

    // Track the location of the * being expanded
    private var starExpansionLocation: Int = 0

    // Use performKeyEquivalent to catch Control+Space before it's consumed
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Check for Control + Space to trigger completion
        if event.modifierFlags.contains(.control) && event.keyCode == 49 {
            print("[Completion] Control+Space detected")
            triggerCompletion()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // If completion popup is visible, handle navigation keys
        if completionPopup.isVisible {
            switch event.keyCode {
            case 125: // Down arrow
                completionPopup.selectNext()
                return
            case 126: // Up arrow
                completionPopup.selectPrevious()
                return
            case 36: // Return
                completionPopup.confirmSelection()
                return
            case 53: // Escape
                completionPopup.cancel()
                return
            case 48: // Tab
                completionPopup.confirmSelection()
                return
            default:
                break
            }
        }

        // Check for Cmd + Enter (Return)
        if event.modifierFlags.contains(.command),
            let characters = event.charactersIgnoringModifiers,
            characters == "\r" {
            handleCmdEnter()
            return
        }

        // Check for Escape to close completion
        if event.keyCode == 53 && completionPopup.isVisible {
            completionPopup.cancel()
            return
        }

        super.keyDown(with: event)

        // If completion is visible and user types, filter the results
        if completionPopup.isVisible {
            let currentLocation = selectedRange().location
            if currentLocation > completionStartLocation {
                let filterRange = NSRange(location: completionStartLocation, length: currentLocation - completionStartLocation)
                let filterText = (string as NSString).substring(with: filterRange)
                completionPopup.filter(with: filterText)
            } else {
                completionPopup.hide()
            }
        }
    }

    /// Trigger LSP completion at current cursor position
    private func triggerCompletion() {
        guard let lspManager = lspManager, lspManager.state == .connected else {
            print("[Completion] LSP not connected")
            NSSound.beep()
            return
        }

        // Cancel any existing completion request
        completionTask?.cancel()

        // Record where completion started
        completionStartLocation = selectedRange().location

        // Get cursor position in LSP coordinates
        let (line, character) = positionToLineCharacter(completionStartLocation)
        print("[Completion] Requesting at line \(line), character \(character)")
        print("[Completion] Document text: \(string.prefix(100))...")

        // Get screen position for popup
        let cursorRect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let screenPoint = NSPoint(x: cursorRect.origin.x, y: cursorRect.origin.y)

        // Request completions asynchronously
        completionTask = Task { @MainActor in
            do {
                let completions = try await lspManager.requestCompletions(line: line, character: character)

                guard !Task.isCancelled else { return }

                print("[Completion] Received \(completions.count) items")
                if !completions.isEmpty {
                    print("[Completion] First item: \(completions[0].label)")
                }

                if completions.isEmpty {
                    print("[Completion] No completions returned")
                    NSSound.beep()
                    return
                }

                let displayItems = completions.map { CompletionDisplayItem(from: $0) }
                completionPopup.show(at: screenPoint, items: displayItems)
            } catch {
                print("[LSP] Completion error: \(error)")
                NSSound.beep()
            }
        }
    }

    private func handleCmdEnter() {
        let textToUse: String
        if selectedRange().length > 0 {
            textToUse = (string as NSString).substring(with: selectedRange())
        } else {
            textToUse = string
        }

        guard let onSubmit = onSubmit else { return }
        onSubmit(textToUse)
    }

    // MARK: - CompletionPopupDelegate

    func completionPopup(_ popup: CompletionPopupController, didSelectItem item: CompletionDisplayItem) {
        // Calculate the range to replace (from completion start to current cursor)
        let currentLocation = selectedRange().location
        let replaceLength = currentLocation - completionStartLocation
        let replaceRange = NSRange(location: completionStartLocation, length: replaceLength)

        // Insert the completion text
        if shouldChangeText(in: replaceRange, replacementString: item.insertText) {
            replaceCharacters(in: replaceRange, with: item.insertText)
            didChangeText()
        }
    }

    func completionPopupDidCancel(_ popup: CompletionPopupController) {
        // Nothing special to do
    }

    // MARK: - Override to handle clicks on * and hide completion

    override func mouseDown(with event: NSEvent) {
        completionPopup.hide()
        columnExpansionPopup.hide()

        // Check if clicked on a * character in a SELECT context
        let clickPoint = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: clickPoint)

        if charIndex > 0 && charIndex <= string.count {
            // Check character at or before click position
            let checkIndex = min(charIndex, string.count - 1)
            let nsString = string as NSString

            if checkIndex >= 0 && checkIndex < nsString.length {
                let char = nsString.substring(with: NSRange(location: checkIndex, length: 1))

                if char == "*" && isStarInSelectContext(at: checkIndex) {
                    // Found a * in SELECT context - show column expansion
                    showColumnExpansionMenu(at: checkIndex)
                    return
                }
            }
        }

        super.mouseDown(with: event)
    }

    /// Check if the * at the given position is in a SELECT context (not multiplication)
    private func isStarInSelectContext(at position: Int) -> Bool {
        let text = string.lowercased()
        let nsText = text as NSString

        // Look backwards from position to find SELECT keyword
        let beforeStar = nsText.substring(to: position)

        // Find the last SELECT before this position
        guard let selectRange = beforeStar.range(of: "select", options: .backwards) else {
            return false
        }

        // Check there's no FROM between SELECT and *
        let afterSelect = String(beforeStar[selectRange.upperBound...])
        if afterSelect.contains("from") {
            return false
        }

        // Additional check: make sure it's not in a subquery after FROM
        // by counting parentheses
        let parenBalance = afterSelect.reduce(0) { count, char in
            if char == "(" { return count + 1 }
            if char == ")" { return count - 1 }
            return count
        }

        // If we're inside unclosed parentheses, could be a subquery - still allow it
        return true
    }

    /// Show the column expansion menu for the * at the given position
    private func showColumnExpansionMenu(at position: Int) {
        guard let lspManager = lspManager, lspManager.state == .connected else {
            print("[ColumnExpansion] LSP not connected")
            return
        }

        starExpansionLocation = position

        // Get screen position for popup
        let charRange = NSRange(location: position, length: 1)
        let screenRect = firstRect(forCharacterRange: charRange, actualRange: nil)
        let screenPoint = NSPoint(x: screenRect.origin.x, y: screenRect.origin.y)

        // Get LSP position (position after the *)
        let (line, character) = positionToLineCharacter(position + 1)

        print("[ColumnExpansion] Requesting columns at line \(line), character \(character)")

        // Request completions from LSP
        Task { @MainActor in
            do {
                let completions = try await lspManager.requestCompletions(line: line, character: character)

                // Filter to only column-like completions (Field, Property, Variable)
                let columnCompletions = completions.filter { item in
                    guard let kind = item.kind else { return true }
                    return kind == .field || kind == .property || kind == .variable || kind == .text
                }

                print("[ColumnExpansion] Received \(columnCompletions.count) column items")

                if columnCompletions.isEmpty {
                    print("[ColumnExpansion] No columns found")
                    NSSound.beep()
                    return
                }

                // Convert to ColumnItems
                let columns = columnCompletions.map { ColumnItem(from: $0) }

                // Show the expansion popup
                columnExpansionPopup.show(at: screenPoint, columns: columns)

            } catch {
                print("[ColumnExpansion] Error: \(error)")
                NSSound.beep()
            }
        }
    }

    // MARK: - ColumnExpansionDelegate

    func columnExpansion(_ popup: ColumnExpansionPopupController, didSelectColumns columns: [ColumnItem], keepStar: Bool) {
        guard !columns.isEmpty || keepStar else { return }

        // Build the replacement text
        var parts: [String] = []

        if keepStar {
            parts.append("*")
        }

        parts.append(contentsOf: columns.map { $0.displayName })

        let replacementText = parts.joined(separator: ", ")

        // Replace the * with the selected columns
        let replaceRange = NSRange(location: starExpansionLocation, length: 1)

        if shouldChangeText(in: replaceRange, replacementString: replacementText) {
            replaceCharacters(in: replaceRange, with: replacementText)
            didChangeText()
        }
    }

    func columnExpansionDidCancel(_ popup: ColumnExpansionPopupController) {
        // Nothing special to do
    }

    // MARK: - LSP Completions (legacy - for standard NSTextView completion)

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard let lspManager = lspManager, lspManager.state == .connected else {
            return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index)
        }

        // Get current cursor position
        let cursorPosition = selectedRange().location
        let (line, character) = positionToLineCharacter(cursorPosition)

        // Request completions synchronously (blocking is okay for completions popup)
        var completionStrings: [String] = []

        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            do {
                let completions = try await lspManager.requestCompletions(line: line, character: character)
                completionStrings = completions.compactMap { item in
                    // Use insertText if available, otherwise label
                    item.insertText ?? item.label
                }
            } catch {
                print("[LSP] Completion error: \(error)")
            }
            semaphore.signal()
        }

        // Wait with timeout
        let result = semaphore.wait(timeout: .now() + 2.0)
        if result == .timedOut {
            print("[LSP] Completion request timed out")
            return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index)
        }

        if completionStrings.isEmpty {
            return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index)
        }

        index.pointee = 0
        return completionStrings
    }

    /// Convert a character offset to (line, character) for LSP
    private func positionToLineCharacter(_ offset: Int) -> (line: Int, character: Int) {
        let text = string
        var line = 0
        var characterInLine = 0
        var currentOffset = 0

        for char in text {
            if currentOffset >= offset {
                break
            }
            if char == "\n" {
                line += 1
                characterInLine = 0
            } else {
                characterInLine += 1
            }
            currentOffset += 1
        }

        return (line, characterInLine)
    }
}
