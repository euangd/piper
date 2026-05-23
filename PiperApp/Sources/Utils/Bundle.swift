// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

extension Bundle {
    var applicationVersion: String {
        let version = "\(infoDictionary?["CFBundleShortVersionString"] ?? "unknown").\(infoDictionary?["CFBundleVersion"] ?? "unknown")"
        return version.replacingOccurrences(of: "$BUILD_NUMBER", with: "1234")
    }
}
