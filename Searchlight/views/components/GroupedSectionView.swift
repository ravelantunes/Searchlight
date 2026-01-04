//
//  GroupedSectionView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/3/26.
//
//  Copyright (c) 2026 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

/// A System Settings-style grouped section with optional title header
struct GroupedSectionView<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let title = title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.leading, Spacing.xxs)
            }

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
}

#Preview {
    VStack(spacing: Spacing.xl) {
        GroupedSectionView(title: "Connection") {
            Text("Field 1")
                .padding()
            Divider()
            Text("Field 2")
                .padding()
        }

        GroupedSectionView {
            Text("No title section")
                .padding()
        }
    }
    .padding()
    .frame(width: 400)
}
