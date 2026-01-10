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
    
    // Lists all tables grouped by schema
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
    
    // Lists all accessible databases on the server
    func listDatabases() async throws -> [String] {
        let results = try await connectionManager.connection.query(
            query: "SELECT datname FROM pg_database WHERE datistemplate = false AND datallowconn = true ORDER BY datname;"
        )
        return results.map { row in
            try! row["datname"].decode(String.self)
        }
    }
    
    // Retrieves column metadata for a table, including foreign key relationships
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
        return results.enumerated().map { index, row in
            let name = try! row["column_name"].decode((String).self)
            let type = try! row["data_type"].decode((String).self)
            let typeName = try! row["udt_name"].decode((String).self)
            // let typeCategory = try! row["typtype"].decode((String).self) TODO: fix this
            let typeCategory = "b"            
            // Position in this app assumes 0-based, sequential position to render columns and UI elements
            // However, I learned that Postgres doesn't guarantee it to be contiguous (i.e.: if column is removed)
            // So we use index from enumeration, which works similarly as long as it's sorted by ordinal position
            // let position = try! row["ordinal_position"].decode((Int).self)-1 // Convert to 0-index base, since ordinal position starts at 1
            let position = index
            let foreignColumnName = try! row["foreign_column_name"].decode((String?).self)
            let foreignTableName = try! row["foreign_table_name"].decode((String?).self)
            let foreignSchemaName = try! row["foreign_schema_name"].decode((String?).self)
            let column = Column(name: name, type: type, typeName: typeName, typeCategory: typeCategory, position: position, foreignSchemaName: foreignSchemaName, foreignTableName: foreignTableName, foreignColumnName: foreignColumnName)
            return column
        }
    }
    

    // Executes a parameterized SELECT query with pagination, sorting, and filtering
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
    
    // Inserts a new row and returns the inserted row with its ctid
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
    
    // Updates a row identified by its ctid with dirty cell values
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
    
    // Deletes multiple rows identified by their ctids
    func deleteRows(schema: String, table: String, rows: [SelectResultRow]) async throws {
        let ids = Array(Set(rows.map { $0.id }))
        guard !ids.isEmpty else { return }
        let tidList = ids.map { "'\($0)'::tid" }.joined(separator: ",")
        let sql = """
        DELETE FROM "\(schema)"."\(table)"
        WHERE ctid IN (\(tidList));
        """
        _ = try await connectionManager.connection.query(query: sql)
    }
    
    // Parses PostgreSQL binary data into a display-friendly cell value representation
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
            // Binary format
            guard var buf = data.value else {
                print("No value for \(dataType) column \(column.name)")
                return .unparseable
            }

            let jsonData: Data

            if dataType == "jsonb" {
                // First byte is the jsonb version
                guard let version = buf.readInteger(as: UInt8.self) else {
                    print("Failed to read jsonb version for column \(column.name)")
                    return .unparseable
                }

                // Currently only version 1 is valid
                guard version == 1 else {
                    print("Unsupported jsonb version \(version) for column \(column.name)")
                    return .unparseable
                }

                guard let d = buf.readData(length: buf.readableBytes) else {
                    print("Failed to read jsonb payload for column \(column.name)")
                    return .unparseable
                }
                jsonData = d
            } else {
                // `json` in binary mode is just text bytes
                guard let d = buf.readData(length: buf.readableBytes) else {
                    print("Failed to read json payload for column \(column.name)")
                    return .unparseable
                }
                jsonData = d
            }

            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("Failed to decode \(dataType) UTF-8 for column \(column.name)")
                return .unparseable
            }

            return .actual(jsonString)
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
        case "time":
            // Fallback: binary format
            guard var buf = data.value, let micros = buf.readInteger(as: Int64.self) else {
                print("Failed to parse time column \(column.name)")
                return .unparseable
            }

            let totalSeconds = Double(micros) / 1_000_000
            let hours = Int(totalSeconds / 3600)
            let minutes = Int(totalSeconds.truncatingRemainder(dividingBy: 3600) / 60)
            let seconds = totalSeconds.truncatingRemainder(dividingBy: 60)

            // Format as HH:MM:SS[.ffffff]
            let fractional = seconds - floor(seconds)
            let formatted: String
            if fractional == 0 {
                formatted = String(format: "%02d:%02d:%02.0f", hours, minutes, floor(seconds))
            } else {
                formatted = String(format: "%02d:%02d:%06.3f", hours, minutes, seconds)
            }

            return .actual(formatted)
        case "timetz":
            guard var buf = data.value, let micros = buf.readInteger(as: Int64.self), let tzSecondsWest = buf.readInteger(as: Int32.self) else {
                print("Failed to parse timetz column \(column.name)")
                return .unparseable
            }

            let totalSeconds = Double(micros) / 1_000_000
            let hours = Int(totalSeconds / 3600)
            let minutes = Int(totalSeconds.truncatingRemainder(dividingBy: 3600) / 60)
            let seconds = totalSeconds.truncatingRemainder(dividingBy: 60)

            // Offset is "seconds west of UTC", so we invert to get the usual ±east
            let offsetSeconds = -Int(tzSecondsWest)
            let offsetSign = offsetSeconds >= 0 ? "+" : "-"
            let offsetAbs = abs(offsetSeconds)
            let offsetHours = offsetAbs / 3600
            let offsetMinutes = (offsetAbs % 3600) / 60

            let timePart: String
            let fractional = seconds - floor(seconds)
            if fractional == 0 {
                timePart = String(format: "%02d:%02d:%02.0f", hours, minutes, floor(seconds))
            } else {
                timePart = String(format: "%02d:%02d:%06.3f", hours, minutes, seconds)
            }

            let offsetPart = String(format: "%@%02d:%02d", offsetSign, offsetHours, offsetMinutes)
            let formatted = "\(timePart)\(offsetPart)"

            return .actual(formatted)
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

    // MARK: - Table Structure Methods

    /// Fetches complete table structure including columns, indexes, and constraints
    func fetchTableStructure(schemaName: String, tableName: String) async throws -> TableStructure {
        async let columnsTask = fetchColumnDefinitions(schemaName: schemaName, tableName: tableName)
        async let indexesTask = fetchIndexes(schemaName: schemaName, tableName: tableName)
        async let constraintsTask = fetchConstraints(schemaName: schemaName, tableName: tableName)

        let columns = try await columnsTask
        let indexes = try await indexesTask
        let constraints = try await constraintsTask

        return TableStructure(
            schemaName: schemaName,
            tableName: tableName,
            columns: columns,
            indexes: indexes,
            constraints: constraints
        )
    }

    // Fetches detailed column definitions for structure view
    func fetchColumnDefinitions(schemaName: String, tableName: String) async throws -> [ColumnDefinition] {
        let query = """
        SELECT
            c.column_name,
            c.data_type,
            c.udt_name,
            c.ordinal_position,
            c.is_nullable = 'YES' AS is_nullable,
            c.column_default,
            c.character_maximum_length,
            c.numeric_precision,
            c.numeric_scale,
            COALESCE(pk.is_pk, false) AS is_primary_key,
            COALESCE(fk.is_fk, false) AS is_foreign_key,
            fk.foreign_schema,
            fk.foreign_table,
            fk.foreign_column
        FROM information_schema.columns c
        LEFT JOIN (
            SELECT kcu.column_name, true AS is_pk
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
                AND tc.table_schema = kcu.table_schema
            WHERE tc.constraint_type = 'PRIMARY KEY'
                AND tc.table_schema = '\(schemaName)'
                AND tc.table_name = '\(tableName)'
        ) pk ON c.column_name = pk.column_name
        LEFT JOIN (
            SELECT
                kcu.column_name,
                true AS is_fk,
                ccu.table_schema AS foreign_schema,
                ccu.table_name AS foreign_table,
                ccu.column_name AS foreign_column
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
                AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage ccu
                ON tc.constraint_name = ccu.constraint_name
                AND tc.table_schema = ccu.constraint_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
                AND tc.table_schema = '\(schemaName)'
                AND tc.table_name = '\(tableName)'
        ) fk ON c.column_name = fk.column_name
        WHERE c.table_schema = '\(schemaName)'
            AND c.table_name = '\(tableName)'
        ORDER BY c.ordinal_position;
        """

        let results = try await connectionManager.connection.query(query: query)
        return results.map { row in
            let foreignKeyRef: ForeignKeyReference?
            let foreignSchema: String? = (try? row["foreign_schema"].decode(String?.self)) ?? nil
            let foreignTable: String? = (try? row["foreign_table"].decode(String?.self)) ?? nil
            let foreignColumn: String? = (try? row["foreign_column"].decode(String?.self)) ?? nil
            if let fs = foreignSchema, let ft = foreignTable, let fc = foreignColumn {
                foreignKeyRef = ForeignKeyReference(
                    schemaName: fs,
                    tableName: ft,
                    columnName: fc
                )
            } else {
                foreignKeyRef = nil
            }

            return ColumnDefinition(
                name: try! row["column_name"].decode(String.self),
                dataType: try! row["data_type"].decode(String.self),
                udtName: try! row["udt_name"].decode(String.self),
                ordinalPosition: try! row["ordinal_position"].decode(Int.self),
                isNullable: try! row["is_nullable"].decode(Bool.self),
                columnDefault: try? row["column_default"].decode(String?.self) ?? nil,
                characterMaximumLength: try? row["character_maximum_length"].decode(Int?.self) ?? nil,
                numericPrecision: try? row["numeric_precision"].decode(Int?.self) ?? nil,
                numericScale: try? row["numeric_scale"].decode(Int?.self) ?? nil,
                isPrimaryKey: try! row["is_primary_key"].decode(Bool.self),
                isForeignKey: try! row["is_foreign_key"].decode(Bool.self),
                foreignKeyReference: foreignKeyRef
            )
        }
    }

    // Fetches indexes for the specified table
    func fetchIndexes(schemaName: String, tableName: String) async throws -> [IndexDefinition] {
        let query = """
        SELECT
            i.relname AS index_name,
            t.relname AS table_name,
            array_agg(a.attname ORDER BY array_position(ix.indkey, a.attnum))::text AS column_names,
            ix.indisunique AS is_unique,
            ix.indisprimary AS is_primary,
            am.amname AS index_type,
            pg_get_indexdef(ix.indexrelid) AS index_definition
        FROM pg_index ix
        JOIN pg_class i ON ix.indexrelid = i.oid
        JOIN pg_class t ON ix.indrelid = t.oid
        JOIN pg_namespace n ON t.relnamespace = n.oid
        JOIN pg_am am ON i.relam = am.oid
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
        WHERE n.nspname = '\(schemaName)'
            AND t.relname = '\(tableName)'
        GROUP BY i.relname, t.relname, ix.indisunique, ix.indisprimary, am.amname, ix.indexrelid
        ORDER BY i.relname;
        """

        let results = try await connectionManager.connection.query(query: query)
        return results.map { row in
            let columnsRaw = try! row["column_names"].decode(String.self)
            let columns = parsePostgresArray(columnsRaw)

            return IndexDefinition(
                name: try! row["index_name"].decode(String.self),
                tableName: try! row["table_name"].decode(String.self),
                columns: columns,
                isUnique: try! row["is_unique"].decode(Bool.self),
                isPrimaryKey: try! row["is_primary"].decode(Bool.self),
                indexType: try! row["index_type"].decode(String.self),
                indexDefinition: try! row["index_definition"].decode(String.self)
            )
        }
    }

    // Fetches constraints for the specified table
    func fetchConstraints(schemaName: String, tableName: String) async throws -> [ConstraintDefinition] {
        let query = """
        SELECT
            tc.constraint_name,
            tc.constraint_type,
            (array_agg(DISTINCT kcu.column_name) FILTER (WHERE kcu.column_name IS NOT NULL))::text AS columns,
            cc.check_clause,
            ccu.table_schema AS foreign_schema,
            ccu.table_name AS foreign_table,
            ccu.column_name AS foreign_column,
            rc.delete_rule,
            rc.update_rule
        FROM information_schema.table_constraints tc
        LEFT JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
        LEFT JOIN information_schema.check_constraints cc
            ON tc.constraint_name = cc.constraint_name
            AND tc.constraint_schema = cc.constraint_schema
        LEFT JOIN information_schema.constraint_column_usage ccu
            ON tc.constraint_name = ccu.constraint_name
            AND tc.constraint_schema = ccu.constraint_schema
            AND tc.constraint_type = 'FOREIGN KEY'
        LEFT JOIN information_schema.referential_constraints rc
            ON tc.constraint_name = rc.constraint_name
            AND tc.constraint_schema = rc.constraint_schema
        WHERE tc.table_schema = '\(schemaName)'
            AND tc.table_name = '\(tableName)'
        GROUP BY tc.constraint_name, tc.constraint_type, cc.check_clause,
                 ccu.table_schema, ccu.table_name, ccu.column_name,
                 rc.delete_rule, rc.update_rule
        ORDER BY tc.constraint_type, tc.constraint_name;
        """

        let results = try await connectionManager.connection.query(query: query)
        return results.compactMap { row -> ConstraintDefinition? in
            let constraintTypeStr = try! row["constraint_type"].decode(String.self)
            guard let constraintType = ConstraintType(rawValue: constraintTypeStr) else {
                return nil
            }

            let columnsRaw = try? row["columns"].decode(String?.self) ?? nil
            let columns = columnsRaw.map { parsePostgresArray($0) } ?? []

            let foreignKeyRef: ForeignKeyReference?
            if constraintType == .foreignKey {
                let foreignSchema: String? = (try? row["foreign_schema"].decode(String?.self)) ?? nil
                let foreignTable: String? = (try? row["foreign_table"].decode(String?.self)) ?? nil
                let foreignColumn: String? = (try? row["foreign_column"].decode(String?.self)) ?? nil
                if let fs = foreignSchema, let ft = foreignTable, let fc = foreignColumn {
                    foreignKeyRef = ForeignKeyReference(
                        schemaName: fs,
                        tableName: ft,
                        columnName: fc
                    )
                } else {
                    foreignKeyRef = nil
                }
            } else {
                foreignKeyRef = nil
            }

            return ConstraintDefinition(
                name: try! row["constraint_name"].decode(String.self),
                constraintType: constraintType,
                columns: columns,
                checkExpression: try? row["check_clause"].decode(String?.self) ?? nil,
                foreignKeyReference: foreignKeyRef,
                onDelete: try? row["delete_rule"].decode(String?.self) ?? nil,
                onUpdate: try? row["update_rule"].decode(String?.self) ?? nil
            )
        }
    }

    // Helper to parse PostgreSQL array format "{a,b,c}" to Swift array
    private func parsePostgresArray(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        guard !trimmed.isEmpty else { return [] }
        return trimmed.components(separatedBy: ",")
    }

    // MARK: - DDL Modification Methods

    // Adds a new column to the table
    func addColumn(schemaName: String, tableName: String, columnName: String,
                   dataType: String, isNullable: Bool, defaultValue: String?) async throws {
        var ddl = "ALTER TABLE \"\(schemaName)\".\"\(tableName)\" ADD COLUMN \"\(columnName)\" \(dataType)"

        if !isNullable {
            ddl += " NOT NULL"
        }

        if let defaultValue = defaultValue, !defaultValue.isEmpty {
            ddl += " DEFAULT \(defaultValue)"
        }

        ddl += ";"
        _ = try await connectionManager.connection.query(query: ddl)
    }

    // Drops a column from the table
    func dropColumn(schemaName: String, tableName: String, columnName: String) async throws {
        let ddl = "ALTER TABLE \"\(schemaName)\".\"\(tableName)\" DROP COLUMN \"\(columnName)\";"
        _ = try await connectionManager.connection.query(query: ddl)
    }

    // Renames a column
    func renameColumn(schemaName: String, tableName: String, oldName: String, newName: String) async throws {
        let ddl = "ALTER TABLE \"\(schemaName)\".\"\(tableName)\" RENAME COLUMN \"\(oldName)\" TO \"\(newName)\";"
        _ = try await connectionManager.connection.query(query: ddl)
    }

    // Changes a column's data type
    func alterColumnType(schemaName: String, tableName: String, columnName: String,
                         newType: String, usingExpression: String? = nil) async throws {
        var ddl = "ALTER TABLE \"\(schemaName)\".\"\(tableName)\" ALTER COLUMN \"\(columnName)\" TYPE \(newType)"

        if let using = usingExpression {
            ddl += " USING \(using)"
        }

        ddl += ";"
        _ = try await connectionManager.connection.query(query: ddl)
    }

    // Sets or drops NOT NULL constraint
    func alterColumnNullability(schemaName: String, tableName: String, columnName: String,
                                isNullable: Bool) async throws {
        let action = isNullable ? "DROP NOT NULL" : "SET NOT NULL"
        let ddl = "ALTER TABLE \"\(schemaName)\".\"\(tableName)\" ALTER COLUMN \"\(columnName)\" \(action);"
        _ = try await connectionManager.connection.query(query: ddl)
    }

    // Sets or drops column default
    func alterColumnDefault(schemaName: String, tableName: String, columnName: String,
                            defaultValue: String?) async throws {
        let action: String
        if let value = defaultValue, !value.isEmpty {
            action = "SET DEFAULT \(value)"
        } else {
            action = "DROP DEFAULT"
        }
        let ddl = "ALTER TABLE \"\(schemaName)\".\"\(tableName)\" ALTER COLUMN \"\(columnName)\" \(action);"
        _ = try await connectionManager.connection.query(query: ddl)
    }

    // Creates an index
    func createIndex(schemaName: String, tableName: String, indexName: String,
                     columns: [String], isUnique: Bool, indexType: String = "btree") async throws {
        let uniqueClause = isUnique ? "UNIQUE " : ""
        let columnsClause = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        let ddl = "CREATE \(uniqueClause)INDEX \"\(indexName)\" ON \"\(schemaName)\".\"\(tableName)\" USING \(indexType) (\(columnsClause));"
        _ = try await connectionManager.connection.query(query: ddl)
    }

    // Drops an index
    func dropIndex(schemaName: String, indexName: String) async throws {
        let ddl = "DROP INDEX \"\(schemaName)\".\"\(indexName)\";"
        _ = try await connectionManager.connection.query(query: ddl)
    }

    // Adds a constraint
    func addConstraint(schemaName: String, tableName: String, constraintName: String,
                       constraintType: ConstraintType, columns: [String],
                       checkExpression: String? = nil, foreignKeyReference: ForeignKeyReference? = nil,
                       onDelete: String? = nil, onUpdate: String? = nil) async throws {
        var ddl = "ALTER TABLE \"\(schemaName)\".\"\(tableName)\" ADD CONSTRAINT \"\(constraintName)\" "

        let cols = columns.map { "\"\($0)\"" }.joined(separator: ", ")

        switch constraintType {
        case .primaryKey:
            ddl += "PRIMARY KEY (\(cols))"
        case .unique:
            ddl += "UNIQUE (\(cols))"
        case .foreignKey:
            guard let fkRef = foreignKeyReference else {
                throw SearchlightAPIError(description: "Foreign key reference required")
            }
            ddl += "FOREIGN KEY (\(cols)) REFERENCES \"\(fkRef.schemaName)\".\"\(fkRef.tableName)\"(\"\(fkRef.columnName)\")"
            if let onDelete = onDelete {
                ddl += " ON DELETE \(onDelete)"
            }
            if let onUpdate = onUpdate {
                ddl += " ON UPDATE \(onUpdate)"
            }
        case .check:
            guard let checkExpr = checkExpression else {
                throw SearchlightAPIError(description: "Check expression required")
            }
            ddl += "CHECK (\(checkExpr))"
        case .exclusion:
            throw SearchlightAPIError(description: "Exclusion constraints are not supported")
        }

        ddl += ";"
        _ = try await connectionManager.connection.query(query: ddl)
    }

    // Drops a constraint
    func dropConstraint(schemaName: String, tableName: String, constraintName: String) async throws {
        let ddl = "ALTER TABLE \"\(schemaName)\".\"\(tableName)\" DROP CONSTRAINT \"\(constraintName)\";"
        _ = try await connectionManager.connection.query(query: ddl)
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
