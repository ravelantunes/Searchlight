//
//  QuickLookView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/2/25.
//
//  Copyright (c) 2025 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//
import SwiftUI

class QuickLookViewModel: ObservableObject {
    @Published var row: SelectResultRow?
}

// View to show values of a single row
struct QuickLookView: View {
    
    @ObservedObject var viewModel: QuickLookViewModel
    
    var body: some View {
        if viewModel.row == nil {
            VStack {
               ProgressView("Loading...")
                   .progressViewStyle(CircularProgressViewStyle())
                   .padding()
            }
            .transition(.opacity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.row!.cells.indices, id: \.self) { index in
                        let cell = viewModel.row!.cells[index]
                        HStack(alignment: .top) {
                            Text(cell.column.name)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(cell.value.stringRepresentation)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        if index != viewModel.row!.cells.indices.last {
                            Divider()
                        }
                    }
                }
                .padding()
                .cornerRadius(12)
                .shadow(radius: 4)
            }
        }
    }
}
