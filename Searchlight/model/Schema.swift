//
//  Schema.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/7/25.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

struct Schema: Identifiable {
    var id: String { name }
    let name: String
    let tables: [Table]
}
