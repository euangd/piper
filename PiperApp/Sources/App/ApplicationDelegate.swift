// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
#if os(iOS)
import UIKit
typealias AppDelegate = UIResponder & UIApplicationDelegate
#elseif os(macOS)
import AppKit
typealias AppDelegate = NSObject & NSApplicationDelegate
#endif

class ApplicationDelegate: AppDelegate {
#if os(macOS)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
#endif
}
