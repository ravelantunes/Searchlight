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

struct AppKitTextView: NSViewRepresentable {
    @Binding var text: String
    var onQuerySubmit: ((String) -> Void)?

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
                
        // Make sure the textView resizes with the scroll view.
        textView.autoresizingMask = [.width]
        return scrollView
        
     }
     
    func updateNSView(_ nsView: NSScrollView, context: Context) {
         if let textView = nsView.documentView as? NSTextView, textView.string != text {
             textView.string = text
             updateSyntaxHighlighting(in: textView)
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
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AppKitTextView

        init(_ parent: AppKitTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.updateSyntaxHighlighting(in: textView)
        }
    }
}

class TextViewWithSubmit: NSTextView {
    
    // onSubmit Reference
    var onSubmit: ((String) -> Void)?
    
    override func keyDown(with event: NSEvent) {
        // Check for Cmd + Enter (Return)
        if event.modifierFlags.contains(.command),
            let characters = event.charactersIgnoringModifiers,
            characters == "\r" {
            handleCmdEnter()
        } else {
            super.keyDown(with: event)
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
}
