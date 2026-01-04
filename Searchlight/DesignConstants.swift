//
//  DesignConstants.swift
//  Searchlight
//
//  Created by Ravel Antunes on 1/3/26.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import SwiftUI

/// 8-point grid spacing system for consistent layout
enum Spacing {
    /// 4pt - Tight spacing for inline elements
    static let xxs: CGFloat = 4
    /// 8pt - Base unit, used for small gaps
    static let xs: CGFloat = 8
    /// 12pt - Compact spacing
    static let sm: CGFloat = 12
    /// 16pt - Default spacing between elements
    static let md: CGFloat = 16
    /// 20pt - Comfortable spacing
    static let lg: CGFloat = 20
    /// 24pt - Section spacing
    static let xl: CGFloat = 24
    /// 32pt - Large section gaps
    static let xxl: CGFloat = 32
    /// 40pt - Major section separation
    static let xxxl: CGFloat = 40
}

/// Corner radius constants for consistent rounding
enum CornerRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 12
}

/// Form layout metrics
enum FormMetrics {
    static let labelWidth: CGFloat = 100
    static let maxFormWidth: CGFloat = 480
    static let sidebarMinWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 260
}
