//
//  ColumnStatisticsView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 12/23/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI
import Charts


let colors = [
    Color.red, Color.blue, Color.green, Color.yellow, Color.purple, Color.orange, Color.pink, Color.cyan, Color.gray, Color.brown, Color.teal
]

struct ColumnStatistics: Identifiable {
    let id = UUID()
    let tableName: String
    let valueCounts: [String?: Int]
    let uniqueValuesCount: Int?
    let nullValuesCount: Int?
    
    func countsToPieChartSlice() -> [PieChartSlice] {
        
        // Sort valueCounts by value, high-to-low
        let sortedValueCounts = valueCounts.sorted { $0.value > $1.value }
        let totalCount = valueCounts.values.reduce(0, +)
        
        var residualCount = 0
        var slices: [PieChartSlice] = []
        for (index, item) in sortedValueCounts.enumerated() {
            let percentage = Double(item.value) / Double(totalCount)
            if percentage > 0.1 {
                let key = truncated(item.key ?? "Null", maxLength: 10, trailing: "...")            
                slices.append(PieChartSlice(label: key, value: item.value, color: colors[index]))
            } else {
                residualCount += item.value
            }
        }
        if residualCount > 0 {
            slices.append(PieChartSlice(label: "Others", value: residualCount, color: Color.gray))
        }
        
        return slices
    }
}

struct PieChartSlice: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
    let color: Color
}

struct ColumnStatisticsView: View {

    @State var columnStatistics: ColumnStatistics
    
    var body: some View {
        Text("DataFrame Statistics for \(columnStatistics.tableName)")
            .font(.headline)
            .padding(.top, 10)
        Divider()
        Text("Unique Values: \(columnStatistics.uniqueValuesCount!)")
        Text("Null Values: \(columnStatistics.nullValuesCount!)")
        Chart {
            ForEach(columnStatistics.countsToPieChartSlice()) { item in
                SectorMark(
                    angle: .value("Count", item.value),
                    innerRadius: .ratio(0.5), // Creates a donut chart effect
                    angularInset: 1
                )
                .foregroundStyle(item.color)
                .annotation(position: .overlay) {
                    Text("\(item.label)\n\(item.value) rows")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
        Spacer()
    }
}
