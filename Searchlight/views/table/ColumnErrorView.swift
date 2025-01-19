//
//  ColumnErrorView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 12/24/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//
import SwiftUI
import Charts


struct ColumnErrorView: View {

    @State var searchlightAPIError: SearchlightAPIError
    
    var body: some View {
        Text(searchlightAPIError.description)
            .frame(maxWidth: 320)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
    }
}
