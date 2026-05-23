// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import SwiftUI
import PiperAppUtils

struct ModelInfoView: View {
    var info: ModelInfo
    var detailed: Bool = false
    var body: some View {
        Section("app_voice_info") {
            InfoViewRow(title: "model".localized, value: info.name.capitalized)
            InfoViewRow(title: "country".localized, value: info.language.country)
            InfoViewRow(title: "language".localized, value: info.language.language)
            if detailed {
                InfoViewRow(title: "version".localized, value: info.piperVersion)
                InfoViewRow(title: "quality".localized, value: info.audio.quality)
                InfoViewRow(title: "sample_rate".localized, value: String(info.audio.sampleRate))
            }
        }
    }
}
