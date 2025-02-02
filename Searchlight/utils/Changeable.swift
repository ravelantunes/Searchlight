//
//  Changeable.swift
//  Searchlight
//
//  Created by Ravel Antunes on 2/2/25.
//

protocol Changeable {}

// Clones and mutates a single property in a struct
extension Changeable {
    func changing<T>(path: WritableKeyPath<Self, T>, to value: T) -> Self {
        var clone = self
        clone[keyPath: path] = value
        return clone
    }
}
