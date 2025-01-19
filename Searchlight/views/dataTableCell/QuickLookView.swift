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

// View to show values of a single row
struct QuickLookView: View {
    
    var row: SelectResultRow
    
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 8) {
                ForEach(row.cells.indices, id: \.self) { index in
                    let cell = row.cells[index]
                    HStack(alignment: .top) {
                        Text(cell.column.name)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(cell.value.stringRepresentation)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if index != row.cells.indices.last {
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
