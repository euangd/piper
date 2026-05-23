// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation

enum AudioNormalizer {
    static func normalize(_ samples: [Float], targetPeak: Float = 0.98) -> [Float] {
        guard !samples.isEmpty else {
            return []
        }

        let peak = samples.reduce(0) { max($0, abs($1)) }
        guard peak > 0 else {
            return samples
        }

        let scale = targetPeak / peak
        return samples.map { $0 * scale }
    }
}
