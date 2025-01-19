//
//  SQLParserTests.swift
//  Searchlight
//
//  Created by Ravel Antunes on 11/10/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import XCTest
@testable import SQLParser

final class MyLibraryTests: XCTestCase {
    func testExample() throws {
        let tokens = tokenize("SELECT * FROM user WHERE id = 123 AND \"first_name\" = 'John'")
        XCTAssertEqual(tokens[0], TokenType.keyword(Keyword._select, NSRange(location: 0, length: 6)))
        XCTAssertEqual(tokens[1], TokenType.symbol("*", NSRange(location: 7, length: 1)))
        XCTAssertEqual(tokens[2], TokenType.keyword(Keyword._from, NSRange(location: 9, length: 4)))
        XCTAssertEqual(tokens[3], TokenType.identifier("user", NSRange(location: 14, length: 4)))
        XCTAssertEqual(tokens[4], TokenType.keyword(Keyword._where, NSRange(location: 19, length: 5)))
        XCTAssertEqual(tokens[5], TokenType.identifier("id", NSRange(location: 25, length: 2)))
        XCTAssertEqual(tokens[6], TokenType.symbol("=", NSRange(location: 28, length: 1)))
        XCTAssertEqual(tokens[7], TokenType.number(123, NSRange(location: 30, length: 3)))
        XCTAssertEqual(tokens[8], TokenType.keyword(Keyword._and, NSRange(location: 34, length: 3)))
        XCTAssertEqual(tokens[9], TokenType.identifier("\"first_name\"", NSRange(location: 38, length: 12)))
        XCTAssertEqual(tokens[10], TokenType.symbol("=", NSRange(location: 51, length: 1)))
        XCTAssertEqual(tokens[11], TokenType.string("John", NSRange(location: 53, length: 6)))
    }
}
