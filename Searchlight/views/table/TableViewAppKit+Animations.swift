//
//  TableViewAppKit+Animations.swift
//  Searchlight
//
//  Created by Ravel Antunes on 9/14/25.
//
//  Copyright (c) 2025 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import AppKit

extension TableViewAppKit {
    
    
    /// Subtle, non-intrusive visual feedback for a successfully updated row.
    /// If the row is visible, it overlays a tinted view that quickly fades out.
    ///
    /// - Parameters:
    ///   - row: Row index to flash.
    ///   - color: Base tint color (alpha is applied below).
    ///   - alpha: Max alpha for the overlay at the peak of the animation.
    ///   - fadeIn: Duration of the quick fade-in.
    ///   - hold: Time to keep the overlay before fading out.
    ///   - fadeOut: Duration of the fade-out.
    ///   - cornerRadius: Corner radius for the overlay.
    ///   - inset: Inset inside the row bounds so it doesn’t butt up against edges.
    ///   TODO: move to an extension
    func flashRow(_ row: Int,
                  color: NSColor = .controlAccentColor,
                  alpha: CGFloat = 0.25,
                  fadeIn: TimeInterval = 0.08,
                  hold: TimeInterval = 0.20,
                  fadeOut: TimeInterval = 0.45,
                  cornerRadius: CGFloat = 6,
                  inset: CGFloat = 2) {
        guard row >= 0, row < tableView.numberOfRows else { return }
        
        // Only animate if the row view is currently realized/visible.
        guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) else { return }
        
        // Create a lightweight overlay that tracks the row's size.
        let overlay = NSView(frame: rowView.bounds.insetBy(dx: inset, dy: inset))
        overlay.wantsLayer = true
        overlay.translatesAutoresizingMaskIntoConstraints = false
        
        if overlay.layer == nil {
            overlay.wantsLayer = true
        }
        overlay.layer?.backgroundColor = color.withAlphaComponent(alpha).cgColor
        overlay.layer?.cornerRadius = cornerRadius
        overlay.alphaValue = 0
        
        rowView.addSubview(overlay)
        
        // Pin overlay to rowView with insets so it resizes with layout changes.
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: inset),
            overlay.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -inset),
            overlay.topAnchor.constraint(equalTo: rowView.topAnchor, constant: inset),
            overlay.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -inset),
        ])
        
        // Animate: quick fade-in, brief hold, smooth fade-out, then remove.
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fadeIn
                overlay.animator().alphaValue = 1.0
            } completionHandler: {
                DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = fadeOut
                        overlay.animator().alphaValue = 0.0
                    } completionHandler: {
                        overlay.removeFromSuperview()
                    }
                }
            }
        }
    }
}
