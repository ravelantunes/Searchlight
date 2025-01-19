//
//  Cell.swift
//  Searchlight
//
//  Created by Ravel Antunes on 10/19/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

struct Table: Identifiable, Hashable {
    var id: String { name }
    let catalog: String
    let schema: String
    let name: String
    let type: String //BASE TABLE, VIEW
}
