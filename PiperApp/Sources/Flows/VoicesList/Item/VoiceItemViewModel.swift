// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

struct VoiceItemViewModel {
    let voice: Voice
    var isDownloading: Bool = false
    var downloadProgress: Double = 0.0
    var isSampleLoading: Bool = false
    var isPlaying: Bool = false
}
