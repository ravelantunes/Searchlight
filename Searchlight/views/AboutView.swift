//
//  AboutView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/5/26.
//
//  Copyright (c) 2024-2026 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Searchlight"
    }

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)

            Text(appName)
                .font(.system(size: 26, weight: .bold))

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()
                .frame(height: Spacing.xs)

            Text("\u{00A9} 2024-2026 Ravel Antunes")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button {
                if let url = URL(string: "https://github.com/ravelantunes/Searchlight") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                    Text("View on GitHub")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.lg)
        .frame(width: 280, height: 300)
    }
}

#Preview {
    AboutView()
}
