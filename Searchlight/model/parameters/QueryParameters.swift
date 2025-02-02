//
//  QueryParameters.swift
//  Searchlight
//
//  Created by Ravel Antunes on 6/2/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation

// TODO: need to support complex/nested criterias
struct Filter: Equatable {
    var column: String
    var value: String
    var operatorString: String
    
    static func == (lhs: Filter, rhs: Filter) -> Bool {
        return lhs.column == rhs.column &&
            lhs.value == rhs.value &&
            lhs.operatorString == rhs.operatorString
    }
}

struct QueryParameters: Equatable, Changeable {
    var schemaName: String?
    var tableName: String?
    var sortColumn: String?
    var sortOrder: SortOrder?
    var limit = 100
    var offset = 0
    var filters = [Filter]()
    
    static func == (lhs: QueryParameters, rhs: QueryParameters) -> Bool {
        return lhs.schemaName == rhs.schemaName &&
            lhs.tableName == rhs.tableName &&
            lhs.sortColumn == rhs.sortColumn &&
            lhs.sortOrder == rhs.sortOrder &&
            lhs.limit == rhs.limit &&
            lhs.offset == rhs.offset &&
            lhs.filters == rhs.filters
    }
    
    func filterStatement() -> String {
        if filters.isEmpty {
            return ""
        }
        
        var filterStatement = "WHERE"
        for (index, filter) in filters.enumerated() {
            
            var filterValue = filter.value
            let operatorString = {
                switch filter.operatorString {
                case "equals":
                    return "="
                case "contains":
                    filterValue = "%\(filter.value)%"
                    return "LIKE"                    
                case "starts with":
                    filterValue = "\(filter.value)%"
                    return "LIKE"
                case "ends with":
                    filterValue = "%\(filter.value)"
                    return "LIKE"
                default:
                    return filter.operatorString
                }
            }()
                                    
            filterStatement += " \(filter.column) \(operatorString) '\(filterValue)'"
            
            if index < filters.count - 1 {
                filterStatement += " AND"
            }
        }        
        return filterStatement
    }
    
    
    func sortStatement() -> String {
        guard let sortColumn = sortColumn, let sortOrder = sortOrder else {
            return ""
        }
        
        var sortOrderString: String = ""
        if sortOrder == .forward {
            sortOrderString = "ASC"
        } else if sortOrder == .reverse {
            sortOrderString = "DESC"
        }
        
        return "ORDER BY \(sortColumn) \(sortOrderString)"
    }
    
    func nextPage() -> QueryParameters {
        let newOffset = offset + limit
        return changing(path: \.offset, to: newOffset)
    }
    
    func previousPage() -> QueryParameters {
        let newOffset = max(offset - limit, 0)
        return changing(path: \.offset, to: newOffset)
    }
}
