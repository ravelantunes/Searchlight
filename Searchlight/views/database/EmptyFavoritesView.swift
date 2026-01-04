//
//  EmptyFavoritesView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/4/26.
//
//  Copyright (c) 2026 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

/// Empty state view shown when there are no saved favorites
struct EmptyFavoritesView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "star.leadinghalf.filled")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))

            Text("No Favorites Yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Save connections to quickly access them later")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(nil)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    List {
        Section("Favorites") {
            EmptyFavoritesView()
        }
    }
    .listStyle(.sidebar)
    .frame(width: 260)
}
