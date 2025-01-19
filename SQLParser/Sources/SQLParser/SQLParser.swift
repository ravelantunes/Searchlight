//
//  SQLParser.swift
//  Searchlight
//
//  Created by Ravel Antunes on 11/10/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Foundation

// MARK: - SQL Parser
/// Enum representing SQL Keywords
/// Prefix with _ to avoid conflicts with Swift reserved keywords
public enum Keyword: String {
    case _select = "SELECT"
    case _from = "FROM"
    case _where = "WHERE"
    case _and = "AND"
    case _or = "OR"
    case _not = "NOT"
    case _in = "IN"
    case _like = "LIKE"
    case _between = "BETWEEN"
    case _is = "IS"
    case _null = "NULL"
    case _order = "ORDER"
    case _by = "BY"
    case _asc = "ASC"
    case _desc = "DESC"
    case _limit = "LIMIT"
    case _offset = "OFFSET"
    case _insert = "INSERT"
    case _into = "INTO"
    case _values = "VALUES"
    case _update = "UPDATE"
    case _set = "SET"
    case _delete = "DELETE"
    case _create = "CREATE"
    case _table = "TABLE"
    case _drop = "DROP"
    case _if = "IF"
    case _exists = "EXISTS"
}

public enum TokenType: Equatable, CustomDebugStringConvertible {
    case keyword(Keyword, NSRange)
    case identifier(String, NSRange)
    case string(String, NSRange)
    case number(Double, NSRange)
    case symbol(Character, NSRange)
    
    public var debugDescription: String {
        switch self {
        case .keyword(let keyword, let range):
            return "\(keyword.rawValue) (\(range.location), \(range.length))"
        case .identifier(let identifier, let range):
            return "Identifier: \(identifier) (\(range.location), \(range.length))"
        case .string(let string, let range):
            return "String: \(string) (\(range.location), \(range.length))"
        case .number(let number, let range):
            return "Number: \(number) (\(range.location), \(range.length))"
        case .symbol(let symbol, let range):
            return "Symbol: \(symbol) (\(range.location), \(range.length))"
        }
    }
}

public func tokenize(_ input: String) -> [TokenType] {
    var tokens: [TokenType] = []
    var current = ""
    var currentStart: Int? = nil
    var inString = false
    let symbols = CharacterSet(charactersIn: ";,()=+-*/")
    
    // Flush the current token using its start index and the current index as the token's range end.
    func flush(at index: Int) {
        guard !current.isEmpty, let start = currentStart else { return }
        
        let range = NSRange(location: start, length: index - start)
        if inString {
            tokens.append(.string(current, range))
        } else if let keyword = Keyword(rawValue: current.uppercased()) {
            tokens.append(.keyword(keyword, range))
        } else if let number = Double(current) {
            tokens.append(.number(number, range))
        } else {
            tokens.append(.identifier(current, range))
        }
        current = ""
        currentStart = nil
    }
    
    let characters = Array(input)
    for (index, character) in characters.enumerated() {
        if character == "'" {
            if inString {
                // Ending the string literal. Append character if needed, then flush
                flush(at: index + 1)
                inString = false
            } else {
                // Starting a string literal. Flush any current token and mark start
                flush(at: index)
                inString = true
                
                // Mark the starting index for the string literal (starting after the quote)
                currentStart = index
            }
        } else if symbols.contains(Unicode.Scalar(String(character))!) && !inString {
            // Before adding the symbol, flush any pending token
            flush(at: index)
            let range = NSRange(location: index, length: 1)
            tokens.append(.symbol(character, range))
        } else if character.isWhitespace && !inString {
            // Flush on whie space, as long as we are not in a string
            flush(at: index)
        } else {
            // If starting a new token, record its starting index
            if current.isEmpty {
                currentStart = currentStart ?? index
            }
            current.append(character)
        }
    }
    flush(at: characters.count)
    print((tokens.map {$0.debugDescription}).joined(separator: ", "))
    return tokens
}
