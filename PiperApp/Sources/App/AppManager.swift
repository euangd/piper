// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation

class AppManager {
    static let shared = AppManager()
    let piper = PiperManager()
    lazy var loader = VoiceLoader()
    let engines = EngineRegistry.shared

    init() {
        try? FileManager.default.cleanTemporaryDirectory()
        setupEngines()
    }

    private func setupEngines() {
        let piperEngine = PiperEngine(piper: piper)
        let meloEngine = MeloTTSEngine()
        let kokoroEngine = KokoroTTSEngine()
        let supertonicEngine = SupertonicTTSEngine()
        let kittenEngine = KittenTTSEngine()
        let pocketEngine = PocketTTSEngine()
        engines.register(piperEngine)
        engines.register(meloEngine)
        engines.register(kokoroEngine)
        engines.register(supertonicEngine)
        engines.register(kittenEngine)
        engines.register(pocketEngine)
    }

    deinit {
        try? FileManager.default.cleanTemporaryDirectory()
    }
}
