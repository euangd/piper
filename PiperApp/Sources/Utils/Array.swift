// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

extension Array where Element == URL {
    var model: Element? {
        first { url in
            let ext = url.pathExtension.lowercased()
            return Constants.supportedModelExtensions.contains(ext) || ext == Constants.modelExtension
        }
    }

    var json: Element? {
        first { url in
            url.pathExtension.lowercased() == Constants.jsonModelExtension
        }
    }
}

extension Array where Element == String {
    var model: Element? {
        // Try supported extensions (check lowercase paths)
        for ext in Constants.supportedModelExtensions {
            if let found = first(where: { file in file.lowercased().hasSuffix(".\(ext)") }) {
                return found
            }
        }
        // Fallback to legacy single extension match
        return first(where: { file in
            let lower = file.lowercased()
            return lower.hasSuffix(".\(Constants.modelExtension)") || lower.hasSuffix(Constants.modelExtension)
        })
    }

    var json: Element? {
        first(where: { file in
            let lower = file.lowercased()
            return lower.hasSuffix(".\(Constants.jsonModelExtension)") || lower.hasSuffix(Constants.jsonModelExtension)
        })
    }
}
