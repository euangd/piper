// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

struct VoiceViewModel {
    var paths: FileManager.ModelPaths
    var modelInfo: ModelInfo?
    var isPlaying: Bool = false
    var isImportingText: Bool = false
    var importError: String?
    var selectedSpeaker: Int = 0
    var speed: Float = 1.0
    var isPaused: Bool = false
    var playbackProgress: Float = 0.0
    var timeRemaining: String = ""
    var elapsedTime: String = ""
    var demoText: String = "A rainbow is a meteorological phenomenon that is caused by reflection, refraction and dispersion of light in water droplets resulting in a spectrum of light appearing in the sky."
}
