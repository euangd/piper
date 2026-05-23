// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

class PiperEngine: @unchecked Sendable, TTSEngine {
    let type: TTSEngineType = .piper
    var playbackState: TTSPlaybackState {
        get async { await playbackStateActor }
    }

    private let piper: PiperManager
    private var playbackStateActor: TTSPlaybackState = .stopped

    init(piper: PiperManager) {
        self.piper = piper
    }

    func play(text: String, voice: VoiceModel, speakerId: Int, speed: Float) async {
        guard let modelInfo = voice.info,
              let paths = FileManager.ModelPaths.installedModel(matching: modelInfo, engine: .piper),
              paths.exist else { return }

        playbackStateActor = .playing
        await piper.playSample(demoText: text,
                              speakerId: speakerId,
                              modelInfo: modelInfo)
        playbackStateActor = .stopped
    }

    func stop() async {
        await piper.stopPlaying()
        playbackStateActor = .stopped
    }

    func pause() async {
        piper.pausePlaying()
        playbackStateActor = .paused
    }

    func resume() async {
        piper.resumePlaying()
        playbackStateActor = .playing
    }

    func synthesize(text: String, to file: String, voice: VoiceModel, speakerId: Int, speed: Float) async throws {
        guard let modelInfo = voice.info else { return }
        try await piper.synthesizeToFile(text: text, to: file, speakerId: speakerId, modelInfo: modelInfo)
    }
}
