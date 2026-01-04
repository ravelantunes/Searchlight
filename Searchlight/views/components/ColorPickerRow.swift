//
//  ColorPickerRow.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/3/26.

//  Copyright (c) 2026 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

/// A color picker row with circular color buttons
struct ColorPickerRow: View {
    @Binding var selectedColorHex: String?

    private let predefinedColors: [(name: String, hex: String)] = [
        ("Red", "#FF6B6B"),
        ("Orange", "#FFA94D"),
        ("Green", "#51CF66"),
        ("Blue", "#4DABF7"),
        ("Purple", "#CC5DE8"),
        ("Pink", "#FF6B9D")
    ]

    private let buttonSize: CGFloat = 24

    var body: some View {
        FormFieldRow(label: "Color", showDivider: false) {
            HStack(spacing: Spacing.sm) {
                // No color button
                colorButton(hex: nil, isSelected: selectedColorHex == nil) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        Image(systemName: "circle.slash")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .help("No color")

                ForEach(predefinedColors, id: \.hex) { colorOption in
                    colorButton(
                        hex: colorOption.hex,
                        isSelected: selectedColorHex == colorOption.hex
                    ) {
                        Circle()
                            .fill(hexToColor(colorOption.hex))
                    }
                    .help(colorOption.name)
                }
            }
        }
    }

    private func colorButton<Content: View>(
        hex: String?,
        isSelected: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedColorHex = hex
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    .frame(width: buttonSize + 6, height: buttonSize + 6)

                content()
                    .frame(width: buttonSize, height: buttonSize)
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
    }

    private func hexToColor(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

#Preview {
    GroupedSectionView(title: "Appearance") {        
        ColorPickerRow(selectedColorHex: .constant("#4DABF7"))
    }
    .padding()
    .frame(width: 400)
}
