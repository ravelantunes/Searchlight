//
//  StringUtils.swift
//  Searchlight
//
//  Created by Ravel Antunes on 12/23/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//
// Truncates the string to a maximum length
func truncated(_ string: String, maxLength: Int, trailing: String) -> String {
    if string.count <= maxLength {
        return string
    }
    
    let truncatedString = String(string[..<string.index(string.startIndex, offsetBy: maxLength)])
    return truncatedString + trailing
}
