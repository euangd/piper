// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

enum TTSPlaybackState: Sendable {
    case stopped
    case playing
    case paused
}

protocol TTSEngine: AnyObject, Sendable {
    var type: TTSEngineType { get }
    var playbackState: TTSPlaybackState { get async }

    func play(text: String, voice: VoiceModel, speakerId: Int, speed: Float) async
    func stop() async
    func pause() async
    func resume() async
    func synthesize(text: String, to file: String, voice: VoiceModel, speakerId: Int, speed: Float) async throws
}
