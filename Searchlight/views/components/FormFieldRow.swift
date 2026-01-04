//
//  FormFieldRow.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/3/26.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

/// A consistent form row with right-aligned label and content area
struct FormFieldRow<Content: View>: View {
    let label: String
    let content: Content
    let showDivider: Bool

    init(label: String, showDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.label = label
        self.showDivider = showDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                Text(label)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(width: FormMetrics.labelWidth, alignment: .trailing)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            if showDivider {
                Divider()
                    .padding(.leading, FormMetrics.labelWidth + Spacing.md + Spacing.md)
            }
        }
    }
}

/// Convenience wrapper for text fields
struct FormTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let showDivider: Bool
    var isSecure: Bool = false

    init(label: String, text: Binding<String>, placeholder: String, showDivider: Bool = true, isSecure: Bool = false) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.showDivider = showDivider
        self.isSecure = isSecure
    }

    var body: some View {
        FormFieldRow(label: label, showDivider: showDivider) {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.plain)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
            }
        }
    }
}

/// Convenience wrapper for number fields
struct FormNumberField: View {
    let label: String
    @Binding var value: Int?
    let placeholder: String
    let showDivider: Bool

    init(label: String, value: Binding<Int?>, placeholder: String, showDivider: Bool = true) {
        self.label = label
        self._value = value
        self.placeholder = placeholder
        self.showDivider = showDivider
    }

    var body: some View {
        FormFieldRow(label: label, showDivider: showDivider) {
            TextField(placeholder, value: $value, formatter: NumberFormatter())
                .textFieldStyle(.plain)
        }
    }
}

#Preview {
    GroupedSectionView(title: "Connection") {
        FormTextField(label: "Host", text: .constant("localhost"), placeholder: "localhost")
        FormNumberField(label: "Port", value: .constant(5432), placeholder: "5432")
        FormTextField(label: "Password", text: .constant(""), placeholder: "Enter password", showDivider: false, isSecure: true)
    }
    .padding()
    .frame(width: 400)
}
