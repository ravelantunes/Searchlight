//
//  TableFilter.swift
//  Searchlight
//
//  Created by Ravel Antunes on 10/19/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

struct FilterOperator: Identifiable {
    let id: String
    let operatorString: String

    init(_ operatorString: String) {
        self.id = operatorString
        self.operatorString = operatorString
    }
}

struct TableFilter: View {
    
    @State private var selectedFilterColumn: Column?
    @State private var selectedFilterOperator: String = ""
    @State private var selectedFilterValue: String = ""
    @State var operationOptions = [
        FilterOperator("equals")
    ]

    var columns: [Column] = []
    @Binding var queryParams: QueryParameters

    var body: some View {
        HStack() {
            Picker("", selection: $selectedFilterColumn) {
                ForEach(columns) { column in
                    Text(column.name).tag(column)
                }
            }
            Picker("", selection: $selectedFilterOperator) {
                ForEach(operationOptions) { option in
                    Text(option.operatorString).tag(option.operatorString)
                }
            }
            .frame(width: 120)
            TextField("", text: $selectedFilterValue)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    self.queryParams = QueryParameters(schemaName: queryParams.schemaName, tableName: queryParams.tableName, sortColumn: queryParams.sortColumn, sortOrder: queryParams.sortOrder, limit: queryParams.limit, filters: [Filter(column: selectedFilterColumn!.name, value: self.selectedFilterValue, operatorString: selectedFilterOperator)])
                }
            Button("Clear") {
                resetFiltersUI()
                self.queryParams = QueryParameters(schemaName: queryParams.schemaName, tableName: queryParams.tableName, sortColumn: queryParams.sortColumn, sortOrder: queryParams.sortOrder, limit: queryParams.limit, filters: [])
            }
        }
        .padding(8)
        .onChange(of: columns) {
            selectedFilterColumn = columns.first
            selectedFilterOperator = operationOptions.first!.operatorString
        }
        .onChange(of: selectedFilterColumn) { oldColumn, newColumn in
            switch newColumn?.typeName {
            case "timestamp":
                operationOptions = [FilterOperator("equals"), FilterOperator("greaterThan"), FilterOperator("lessThan")]
            case "varchar", "uuid", "text":
                operationOptions = [FilterOperator("equals"), FilterOperator("contains")]
            default:
                operationOptions = [FilterOperator("equals")]
            }
        }        
    }
    
    private func resetFiltersUI() {
        self.selectedFilterColumn = nil
        self.selectedFilterOperator = ""
        self.selectedFilterValue = ""
    }
}
