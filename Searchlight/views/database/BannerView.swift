//
//  BannerView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 11/11/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//
import SwiftUI

struct BannerView: View {
    @Binding var showBanner: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("⚠️ Early Stage Project: Work in Progress")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    withAnimation {
                        showBanner = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding([.top, .horizontal])
            Text("Thank you for using my app! This project is in early development and not recommended for production use. Please report any issues by opening a GitHub issue.")
                .font(.subheadline)
                .foregroundColor(.white)
                .padding([.bottom, .horizontal])
        }
        .background(
            RadialGradient(
                gradient: Gradient(colors: [Color(red: 0.8, green: 0.2, blue: 0.2), Color(red: 0.6, green: 0, blue: 0)]),
                center: .center,
                startRadius: 5,
                endRadius: 200
            )
        )
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding([.horizontal, .vertical])
    }
}
