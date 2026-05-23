// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation

public enum TTSEngineType: String, Codable, Sendable {
    case piper
    case meloTTS
    case kokoro
    case supertonic3
    case kittenTTS
    case pocketTTS

    public var displayName: String {
        switch self {
        case .piper:
            return "Piper"
        case .meloTTS:
            return "MeloTTS"
        case .kokoro:
            return "Kokoro"
        case .supertonic3:
            return "Supertonic 3"
        case .kittenTTS:
            return "Kitten TTS"
        case .pocketTTS:
            return "Pocket TTS"
        }
    }
}
