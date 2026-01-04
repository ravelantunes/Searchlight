//
//  CompactBannerView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/4/26.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

/// A compact, non-intrusive banner for displaying app status messages
struct CompactBannerView: View {
    @Binding var showBanner: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "flask")
                .foregroundColor(.orange)

            Text("Early Preview")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("This app is in active development.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showBanner = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.orange.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.orange.opacity(0.2)),
            alignment: .bottom
        )
    }
}

#Preview {
    VStack(spacing: 0) {
        CompactBannerView(showBanner: .constant(true))
        Spacer()
    }
    .frame(width: 500, height: 300)
}
