//
//  ColumnStatisticsViewController.swift
//  Searchlight
//
//  Created by Ravel Antunes on 12/23/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import Cocoa
import SwiftUI

class ColumnStatisticsViewController: NSViewController {
    var columnStatistics: ColumnStatistics
    
    init(columnStatistics: ColumnStatistics) {
        self.columnStatistics = columnStatistics
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = ColumnStatisticsView(columnStatistics: columnStatistics)
        self.view = NSHostingView(rootView: view)
    }
}
