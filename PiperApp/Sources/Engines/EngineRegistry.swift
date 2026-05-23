// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

final class EngineRegistry: @unchecked Sendable {
    static let shared = EngineRegistry()

    private var engines: [TTSEngineType: any TTSEngine] = [:]

    private init() {}

    func register(_ engine: any TTSEngine) {
        engines[engine.type] = engine
    }

    func engine(for type: TTSEngineType) -> (any TTSEngine)? {
        engines[type]
    }

    func engine(for model: VoiceModel) -> (any TTSEngine)? {
        engines[model.engine]
    }

    var installedVoices: [VoiceModel] {
        var voices: [VoiceModel] = []

        for modelPaths in FileManager.ModelPaths.installedModels {
            if engines[modelPaths.engine] != nil,
               let info = modelPaths.info {
                voices.append(VoiceModel(engine: modelPaths.engine, info: info))
            }
        }

        return voices.sorted { $0.info?.name ?? "" < $1.info?.name ?? "" }
    }
}
