//
//  PostgresDatabaseAPI.swift
//  Searchlight
//
//  Created by Ravel Antunes on 9/28/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation
import PostgresNIO
import PostgresKit

class PostgresDatabaseAPI: ObservableObject {
    
    let connectionManager: ConnectionsManager 
    
    required init(connectionManager: ConnectionsManager) {
        self.connectionManager = connectionManager
    }
    
    // Executes a query based on a string.
    // This should only be used from query editor.
    func execute(_ query: String) async throws -> SelectResult {
        // Run the arbitrary query.
        let rows = try await connectionManager.connection.query(query: query)
        
        // If no rows were returned, return an empty result.
        guard let firstRow = rows.first else {
            return SelectResult(columns: [], rows: [], tableName: nil)
        }
        
        // Build a list of columns from the first row. Here we use each column's metadata.
        // TODO: review if there's a better way and that includes column information even with empty result
        let columns: [Column] = (0..<firstRow.endIndex).map { index in
            let r = firstRow[index]
            return Column(
                name: r.columnName,
                type: "unknown",
                typeName: r.dataType.knownSQLName?.lowercased() ?? "unknown",
                typeCategory: "unknown",
                position: index,
                foreignSchemaName: nil,
                foreignTableName: nil,
                foreignColumnName: nil
            )
        }
        
        let mappedRows: [SelectResultRow] = rows.enumerated().map { (rowIndex, row) in
            let mappedColumns = columns.enumerated().map { (columnIndex, column) in
                let cellValue = parseCellValue(data: row[data: column.name], column: column)
                return Cell(column: column, value: cellValue, position: rowIndex)
            }
            return SelectResultRow(id: "", cells: mappedColumns)
        }
        
        return SelectResult(columns: columns, rows: mappedRows, tableName: nil)
    }
    
    func listTables() async throws -> [Schema] {
        let results = try await connectionManager.connection.query(query: "SELECT table_catalog, table_schema, table_name, table_type FROM information_schema.tables WHERE table_type = 'BASE TABLE' ORDER BY table_name;")
        
        // To prevent modifying list of tables on Schema, we initially just keep track of the list of tables using this map, an create the Schema object at the end
        var schemaMap: [String: [Table]] = [:]
        _ = results.map {row in
            let catalogName = try! row["table_catalog"].decode((String).self)
            let schemaName = try! row["table_schema"].decode((String).self)
            let tableName = try! row["table_name"].decode((String).self)
            let tableType = try! row["table_type"].decode((String).self)
            
            if schemaMap[schemaName] == nil {
                schemaMap[schemaName] = []
            }
            schemaMap[schemaName]?.append(Table(catalog: catalogName, schema: schemaName, name: tableName, type: tableType))
            
            return Table(catalog: catalogName, schema: schemaName, name: tableName, type: tableType)
        }
        let schemas = schemaMap.map(Schema.init(name:tables:))
        return schemas
    }
    
    func listDatabases() async throws -> [String] {
        let results = try await connectionManager.connection.query(
            query: "SELECT datname FROM pg_database WHERE datistemplate = false AND datallowconn = true ORDER BY datname;"
        )
        return results.map { row in
            try! row["datname"].decode(String.self)
        }
    }
    
    func describeTable(tableName: String, schemaName: String) async throws -> [Column] {
        let describeTableQueryString = """
        SELECT
            c.column_name,
            c.data_type,
            c.udt_name,
            c.ordinal_position,            
            STRING_AGG(DISTINCT ccu.table_name, ', ') AS foreign_table_name,            
            STRING_AGG(DISTINCT ccu.column_name, ', ') AS foreign_column_name,
            STRING_AGG(DISTINCT ccu.table_schema, ', ') AS foreign_schema_name
        FROM
            information_schema.columns c
        LEFT JOIN
            information_schema.key_column_usage kcu
            ON c.table_schema = kcu.table_schema
            AND c.table_name = kcu.table_name
            AND c.column_name = kcu.column_name
        LEFT JOIN
            information_schema.table_constraints tc
            ON kcu.constraint_schema = tc.constraint_schema
            AND kcu.constraint_name = tc.constraint_name
            AND tc.constraint_type = 'FOREIGN KEY'
        LEFT JOIN
            information_schema.constraint_column_usage ccu
            ON tc.constraint_schema = ccu.constraint_schema
            AND tc.constraint_name = ccu.constraint_name
        WHERE
            c.table_name = '\(tableName)'
            AND c.table_schema = '\(schemaName)'
        GROUP BY
            c.column_name,
            c.data_type,
            c.udt_name,
            c.ordinal_position
        ORDER BY
            c.ordinal_position;
        """
        let results = try await connectionManager.connection.query(query: describeTableQueryString)
        return results.map { row in
            let name = try! row["column_name"].decode((String).self)
            let type = try! row["data_type"].decode((String).self)
            let typeName = try! row["udt_name"].decode((String).self)
            // let typeCategory = try! row["typtype"].decode((String).self) TODO: fix this
            let typeCategory = "b"
            let position = try! row["ordinal_position"].decode((Int).self)-1 // Convert to 0-index base, since ordinal position starts at 1
            let foreignColumnName = try! row["foreign_column_name"].decode((String?).self)
            let foreignTableName = try! row["foreign_table_name"].decode((String?).self)
            let foreignSchemaName = try! row["foreign_schema_name"].decode((String?).self)
            let column = Column(name: name, type: type, typeName: typeName, typeCategory: typeCategory, position: position, foreignSchemaName: foreignSchemaName, foreignTableName: foreignTableName, foreignColumnName: foreignColumnName)
            return column
        }
    }
    

    func select(params: QueryParameters) async throws -> SelectResult {
        
        guard let tableName = params.tableName, let schemaName = params.schemaName else {
            // TODO: error handling
            throw NSError(domain: "postgress", code: 0, userInfo: nil)
        }
        
        let query = "SELECT *, ctid::text FROM \"\(schemaName)\".\"\(tableName)\" \(params.filterStatement()) \(params.sortStatement()) LIMIT \(params.limit) OFFSET \(params.offset);"
        
        async let selectTask = try await connectionManager.connection.query(query: query)
        async let describeTask = try describeTable(tableName: tableName, schemaName: schemaName)
        
        // Perform both queries in parallel
        let tableRows = try await selectTask
        var columns = try await describeTask
        columns.insert(Column(name: "ctid", type: "ctid", typeName: "ctid", typeCategory: "b", position: columns.count, foreignSchemaName: nil, foreignTableName: nil, foreignColumnName: nil), at: columns.count)
        
        let mappedRows: [[Cell]] = tableRows.enumerated().map { (rowIndex, row) in
            let mappedColumns = columns.enumerated().map { (columnIndex, column) in
                let cellValue = parseCellValue(data: row[data: column.name], column: column)
                return Cell(column: column, value: cellValue, position: rowIndex)
            }
            return mappedColumns
        }
        
        let mappedToSelectResultRow = mappedRows.enumerated().map { (index, row) in
            guard let ctidCell = row.last, ctidCell.column.name == "ctid" else {
                fatalError("ctid column not found")
            }
            
            // Remove last cell since we don't need to display ctid
            let allItemsExceptLast = row.dropLast().map { $0 }
            
            return SelectResultRow(id: ctidCell.value.stringRepresentation, cells: allItemsExceptLast)
        }
        
        // Remove ctid from columns
        columns.removeLast()
 
        return SelectResult(columns: columns, rows: mappedToSelectResultRow, tableName: params.tableName)
    }
    
    func insertRow(schemaName: String, tableName: String, row: SelectResultRow) async throws -> SelectResultRow {
        // Build INSERT statement
        var columnsPart = ""
        var valuesPart = ""
        for (index, cell) in row.cells.enumerated() {
            columnsPart += cell.column.name
            valuesPart += cell.value.sqlValueString
            if index < row.cells.count - 1 {
                columnsPart += ", "
                valuesPart += ", "
            }
        }
        
        // Return all columns plus ctid so we can build the SelectResultRow id
        let query = "INSERT INTO \"\(schemaName)\".\"\(tableName)\" (\(columnsPart)) VALUES (\(valuesPart)) RETURNING *, ctid::text;"

        // Run INSERT and describe table in parallel (so we can map cells consistently)
        async let insertTask = try await connectionManager.connection.query(query: query)
        
        // TODO: figure out how to re-use the result from select, so we don't do an additional describe here
        async let describeTask = try describeTable(tableName: tableName, schemaName: schemaName)

        let insertRows = try await insertTask
        var columns = try await describeTask
        
        // Append synthetic ctid column to align with RETURNING list
        columns.insert(Column(name: "ctid", type: "ctid", typeName: "ctid", typeCategory: "b", position: columns.count, foreignSchemaName: nil, foreignTableName: nil, foreignColumnName: nil), at: columns.count)

        guard let returned = insertRows.first else {
            // Should not happen because of RETURNING, but handle defensively
            throw SearchlightAPIError(description: "Failed to insert row. INSERT statement returned no rows.")
        }

        // Map the single returned row to our cell representations
        let mappedCells: [Cell] = columns.enumerated().map { (columnIndex, column) in
            let cellValue = parseCellValue(data: returned[data: column.name], column: column)
            return Cell(column: column, value: cellValue, position: 0)
        }

        // Extract ctid as id and drop it from the visible cells
        guard let ctidCell = mappedCells.last, ctidCell.column.name == "ctid" else {
            fatalError("ctid column not found in INSERT RETURNING")
        }
        let visibleCells = mappedCells.dropLast().map { $0 }
        let insertedRow = SelectResultRow(id: ctidCell.value.stringRepresentation, cells: visibleCells)

        return insertedRow
    }
    
    func updateRow(schemaName: String, tableName: String, row: SelectResultRow) async throws -> Void {
        
        // Filter non-dirty or unsupported cells
        let dirtyCells = row.cells.filter { $0.isDirty && $0.value != .unsupported && $0.value != .unparseable }
        guard !dirtyCells.isEmpty else {
            print("Trying to perform an update, but no dirty cells found")
            
            throw SearchlightAPIError(
                description: "Nothing to update"           
            )
        }
        
        var query = "UPDATE \"\(schemaName)\".\"\(tableName)\" SET "
        for (index, cell) in dirtyCells.enumerated() {
            let cellValue = cell.value.sqlValueString
            query += "\(cell.column.name) = \(cellValue)"
            if index < row.cells.count - 1 {
                query += ", "
            }
        }
        query += " WHERE ctid = '\(row.id)';"
        print(query)
        
        _ = try await connectionManager.connection.query(query: query)
    }
    
    func deleteRows(schema: String, table: String, rows: [SelectResultRow]) async throws {
        let ids = Array(Set(rows.map { $0.id }))
        guard !ids.isEmpty else { return }
        let tidList = ids.map { "'\($0)'::tid" }.joined(separator: ",")
        let sql = """
        DELETE FROM "\(schema)"."\(table)"
        WHERE ctid IN (\(tidList));
        """
        try await connectionManager.connection.query(query: sql)
    }
    
    private func parseCellValue(data: PostgresData, column: Column) -> CellValueRepresentation {
        // Determine the PostgreSQL data type
        let dataType = column.typeName.lowercased()
    
        guard var value = data.value else {
            return CellValueRepresentation.null
        }

        switch dataType {
        case "varchar", "text", "char", "bpchar":
            guard let stringValue = data.string else {
                print("Failed to parse column \(column.name) of type \(dataType)")
                return CellValueRepresentation.unparseable
            }
            return CellValueRepresentation.actual(stringValue)
        case "json", "jsonb":
            guard let rawByteBuffer = data.value else {
                return .unparseable
            }
            
            let allBytes = Data(rawByteBuffer.readableBytesView)

            // Postgres json objects comes with U+0001 (Start of Heading) and we need to manually strip it
            if let braceOffset = allBytes.firstIndex(of: UInt8(ascii: "{")) {
                let jsonBytes = allBytes.subdata(in: braceOffset..<allBytes.count)
                if let jsonString = String(data: jsonBytes, encoding: .utf8) {
                    return CellValueRepresentation.actual(jsonString)
                }
            }
     
            return CellValueRepresentation.unparseable
        case "bool", "boolean":
            return CellValueRepresentation.actual(data.bool! ? "true" : "false")
        case "int2", "int4", "int8", "integer", "smallint", "bigint":
            if let intValue = data.int {
                return CellValueRepresentation.actual("\(intValue)")
            }
        case "float4", "float8", "double precision", "numeric", "decimal":
            if let doubleValue = data.double {
                return CellValueRepresentation.actual("\(doubleValue)")
            }
        case "date":
            return CellValueRepresentation.actual(data.string!)
        case "time", "timetz":
            return CellValueRepresentation.unsupported
        case "timestamp", "timestamptz":
            return CellValueRepresentation.actual(data.string!)
        case "int4range", "int8range", "numrange", "tsrange", "tstzrange", "daterange":
            return CellValueRepresentation.unsupported
        case "uuid":
            return CellValueRepresentation.actual(data.string!)
        case "bytea":
            if let d = value.readData(length: value.readableBytes) {
                return CellValueRepresentation.actual(d.base64EncodedString())
            }
        default:
            break
        }

        // Fallback for unsupported types
        if let stringValue = data.string {
            return CellValueRepresentation.actual(stringValue)
        } else {
            print("Failed to parse value from column \(column.name) with type \(dataType)")
            return CellValueRepresentation.unsupported
        }
    }
}

struct SearchlightAPIError: Error, LocalizedError {
    var description: String
    var columnName: String?
    

    var errorDescription: String? {
        if columnName != nil {
            return "\(description) in column: \(String(describing: columnName))"
        }
        
        return description
    }
    
}
