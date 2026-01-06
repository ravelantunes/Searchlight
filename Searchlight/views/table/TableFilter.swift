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

enum FilterOperator: String, CaseIterable, Identifiable {
    case equals = "equals"
    case contains = "contains"
    case isNull = "is NULL"
    case isNotNull = "is not NULL"
    case greaterThan = "greater than"
    case lessThan = "less than"
    case greaterThanOrEqual = "greater or equal"
    case lessThanOrEqual = "less or equal"
    case startsWith = "starts with"
    case endsWith = "ends with"
    
    var id: String { rawValue }

}

struct TableFilter: View {
    
    @State private var selectedFilterColumn: Column?
    @State private var selectedFilterOperator: FilterOperator = .equals
    @State private var selectedFilterValue: String = ""
    @State var operationOptions: [FilterOperator] = []

    var columns: [Column] = []
    @Binding var queryParams: QueryParameters

    var body: some View {
        HStack() {
            Picker("", selection: $selectedFilterColumn) {
                // Hidden placeholder to satisfy SwiftUI’s requirement
                Text("").tag(nil as Column?)
                
                ForEach(columns) { column in
                    Text(column.name).tag(column)
                }
            }
            Picker("", selection: $selectedFilterOperator) {
                // Hidden placeholder to satisfy SwiftUI’s requirement
                Text("").tag(nil as FilterOperator?)
                
                ForEach(operationOptions) { option in
                    Text(option.rawValue)
                        .tag(option)
                }
            }
            .frame(width: 120)
            TextField("", text: $selectedFilterValue)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    submit()
                }
                .disabled($selectedFilterOperator.wrappedValue == .isNull || $selectedFilterOperator.wrappedValue == .isNotNull)
            Button("Apply") {
                submit()
            }
            Button("Clear") {
                resetFiltersUI()
                self.queryParams = QueryParameters(schemaName: queryParams.schemaName, tableName: queryParams.tableName, sortColumn: queryParams.sortColumn, sortOrder: queryParams.sortOrder, limit: queryParams.limit, filters: [])
            }.buttonStyle(.accessoryBar)
        }
        .padding(8)
        .onChange(of: columns) {
            selectedFilterColumn = columns.first
            if !operationOptions.isEmpty {
                selectedFilterOperator = operationOptions.first!
            }
        }
        .onChange(of: selectedFilterColumn) { oldColumn, newColumn in
            switch newColumn?.typeName {
            case "timestamp", "date", "time":
                operationOptions = [.equals, .greaterThan, .lessThan, .greaterThanOrEqual, .lessThanOrEqual, .isNull, .isNotNull]
            case "int2", "int4", "int8", "integer", "smallint", "bigint", "numeric", "decimal", "real", "float4", "float8", "double precision":
                operationOptions = [.equals, .greaterThan, .lessThan, .greaterThanOrEqual, .lessThanOrEqual, .isNull, .isNotNull]
            case "varchar", "uuid", "text":
                operationOptions = [.equals, .contains, .startsWith, .endsWith, .isNull, .isNotNull]
            default:
                operationOptions = [.equals, .isNull, .isNotNull]
            }
        }        
    }
    
    private func submit() {
        self.queryParams = QueryParameters(schemaName: queryParams.schemaName, tableName: queryParams.tableName, sortColumn: queryParams.sortColumn, sortOrder: queryParams.sortOrder, limit: queryParams.limit, filters: [Filter(column: selectedFilterColumn!.name, value: self.selectedFilterValue, operation: selectedFilterOperator)])
    }
    
    private func resetFiltersUI() {
        self.selectedFilterColumn = nil
        self.selectedFilterOperator = .equals
        self.selectedFilterValue = ""
    }
}
