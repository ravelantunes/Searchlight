//
//  PopoverViewController.swift
//  Searchlight
//
//  Created by Ravel Antunes on 12/24/24.
//
//  Copyright (c) 2024 Ravel Antunes
//
//  This software is licensed under the MIT License.
//  You may obtain a copy of the License at https://opensource.org/licenses/MIT
//

import AppKit
import SwiftUI

// A viewcontroller for generic popover displaying
class PopoverViewController: NSViewController {
    
    var swiftUIView: AnyView
    
    // Initialize the view controller passing that SwiftUI view intended to be displayed in the popover
    init<V: View>(with swiftUIView: V) {
        self.swiftUIView = AnyView(swiftUIView)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        preferredContentSize = view.fittingSize
    }
    
    override func loadView() {
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.sizingOptions = [.preferredContentSize]
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view = hostingView
    }
}
