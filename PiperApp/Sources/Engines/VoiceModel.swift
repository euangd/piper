// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

struct VoiceModel: Identifiable, Sendable, Hashable, Equatable {
    var id: String {
        engine.rawValue + ":" + (info?.voiceId ?? "")
    }

    let engine: TTSEngineType
    let info: ModelInfo?

    init(engine: TTSEngineType, info: ModelInfo?) {
        self.engine = engine
        self.info = info
    }

    static func == (lhs: VoiceModel, rhs: VoiceModel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
