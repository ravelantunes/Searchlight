//
//  TableSelectionContentView.swift
//  Searchlight
//
//  Created by Ravel Antunes on 6/12/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation
import SwiftUI

struct TableSelectionContentView: View {
    
    @EnvironmentObject var pgApi: PostgresDatabaseAPI
    @EnvironmentObject var appState: AppState
    
    @State private var schemas = [Schema]()
    @State private var schemaExpansionState: [String: Bool] = [:]
        
    var body: some View {
        List(selection: $appState.selectedTable) {
            Picker("Database", selection: $appState.selectedDatabase) {
                ForEach(appState.databases, id: \.self) {
                    Text($0).tag($0)
                }
            }.pickerStyle(MenuPickerStyle())
            
            Section("Tables") {
                ForEach(schemas) { schema in
                    DisclosureGroup(isExpanded: Binding(get: {
                        schemaExpansionState[schema.name]!
                    }, set: { newValue in
                        schemaExpansionState[schema.name]!.toggle()
                    }), content: {
                        ForEach(schema.tables) { table in
                            NavigationLink(value: table) {
                                Label(table.name, systemImage: "table")
                            }
                        }
                    }, label: {
                        Label(schema.name, systemImage: "folder")
                            .foregroundColor(.indigo)
                            .onTapGesture {
                                schemaExpansionState[schema.name]!.toggle()
                            }
                    })
                }
            }
        }.onAppear {
            refreshTables()
        }
        .onChange(of: appState.selectedDatabase, initial: true) { oldValue, newValue in
            refreshTables()
        }
        .navigationTitle(appState.selectedDatabase!)
    }
    
    private func refreshTables() {
        Task {
            let systemSchemas: Set<String> = [
                "information_schema",
                "pg_catalog",
            ]
            
            // Sort the schemas in a way that puts the non-system schemas first        
            let updatedSchemas = try await pgApi.listTables().sorted { schema1, schema2 in
                let isSystem1 = systemSchemas.contains(schema1.name)
                let isSystem2 = systemSchemas.contains(schema2.name)
                
                switch (isSystem1, isSystem2) {
                case (false, true):
                    // schema1 is user, schema2 is system
                    return true
                case (true, false):
                    // schema1 is system, schema2 is user
                    return false
                default:
                    return schema1.name.lowercased() < schema2.name.lowercased()
                }
            }
            
            withAnimation {
                schemas = updatedSchemas
                
                // Initialize expansion state. Tries to set the public schema as expanded by default, if it exists.
                var hasPublicNamedSchema = false
                for schema in schemas {
                    if schema.name == "public" {
                        hasPublicNamedSchema = true
                        schemaExpansionState[schema.name] = true
                    } else {
                        schemaExpansionState[schema.name] = false
                    }
                }
                
                // If public schema doesn't exists, expand the first schema by default
                if !hasPublicNamedSchema && schemas.count > 0 {
                    schemaExpansionState[schemas.first!.name] = true
                }
            }
        }
    }
}

struct TableSelectionContentView_Previews: PreviewProvider {
    static var previews: some View {
        TableSelectionContentView()
    }
}
