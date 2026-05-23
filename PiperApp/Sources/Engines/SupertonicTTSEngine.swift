// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils
import AVFoundation

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

final class SupertonicTTSEngine: @unchecked Sendable, TTSEngine {
    enum Error: Swift.Error {
        case runtimeUnavailable
        case modelLoadFailed(String)
        case tokenizationFailed
        case inferenceFailed(String)
    }

    let type: TTSEngineType = .supertonic3
    var playbackState: TTSPlaybackState {
        get async { state }
    }

    private var state: TTSPlaybackState = .stopped
    private let sessionStore = ONNXSessionStore()
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var continuation: CheckedContinuation<Void, Never>?

    func play(text: String, voice: VoiceModel, speakerId: Int, speed: Float) async {
        guard ONNXRuntimeSupport.isAvailable else {
            Log.warning(type: .synthesizer, "Supertonic 3 requested, but ONNX Runtime is unavailable")
            return
        }

        Log.info(type: .synthesizer, "Supertonic 3 playback requested for voice \(voice.id), speakerId: \(speakerId), speed: \(speed)")
        state = .playing

        do {
            let samples = try await runInference(text: text, voice: voice, speakerId: speakerId, speed: speed)
            let sampleRate = voice.info?.audio.sampleRate ?? 44100.0

            stopPlayingAudio()

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)

            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
            engine.connect(player, to: engine.mainMixerNode, format: format)

            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buffer.frameLength = AVAudioFrameCount(samples.count)
            let channelData = buffer.floatChannelData![0]
            for i in 0..<samples.count {
                channelData[i] = samples[i]
            }

            try engine.start()
            player.play()

            self.audioEngine = engine
            self.playerNode = player

            await withCheckedContinuation { [weak self] continuation in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                self.continuation = continuation
                player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
                    self?.resumeContinuation()
                })
            }

            stopPlayingAudio()
            state = .stopped

        } catch {
            Log.error("Supertonic 3 playback error: \(error)")
            stopPlayingAudio()
            resumeContinuation()
            state = .stopped
        }
    }

    func stop() async {
        stopPlayingAudio()
        resumeContinuation()
        state = .stopped
    }

    func pause() async {
        guard state == .playing else { return }
        playerNode?.pause()
        state = .paused
    }

    func resume() async {
        guard state == .paused else { return }
        playerNode?.play()
        state = .playing
    }

    private func stopPlayingAudio() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
    }

    private func resumeContinuation() {
        continuation?.resume()
        continuation = nil
    }

    func synthesize(text: String, to file: String, voice: VoiceModel, speakerId: Int, speed: Float) async throws {
        guard ONNXRuntimeSupport.isAvailable else {
            throw Error.runtimeUnavailable
        }

        Log.info(type: .synthesizer, "Supertonic 3 file synthesis requested to \(file), speed: \(speed)")

        let samples = try await runInference(text: text, voice: voice, speakerId: speakerId, speed: speed)
        let sampleRate = voice.info?.audio.sampleRate ?? 44100.0

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = samples[i]
        }

        let fileURL = URL(fileURLWithPath: file)
        try? FileManager.default.removeItem(at: fileURL)

        let audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try audioFile.write(from: buffer)
    }

    #if canImport(OnnxRuntimeBindings)
    private func runInference(text: String, voice: VoiceModel, speakerId: Int, speed: Float) async throws -> [Float] {
        guard let modelInfo = voice.info,
              let paths = FileManager.ModelPaths.installedModel(matching: modelInfo, engine: .supertonic3),
              paths.exist,
              let folder = paths.modelFolder else {
            throw Error.modelLoadFailed("Missing model files or directory")
        }

        let textEncoderPath = folder.appendingPathComponent("text_encoder.onnx")
        let durationPredictorPath = folder.appendingPathComponent("duration_predictor.onnx")
        let decoderPath = folder.appendingPathComponent("decoder.onnx")

        let env = try ORTEnv(loggingLevel: .warning)

        // 1. Text Encoder Session
        let encoderSession = try await sessionStore.session(for: textEncoderPath.path) { path in
            try ORTSession(env: env, modelPath: path, sessionOptions: nil)
        }

        // 2. Duration Predictor Session
        let durationSession = try await sessionStore.session(for: durationPredictorPath.path) { path in
            try ORTSession(env: env, modelPath: path, sessionOptions: nil)
        }

        // 3. Decoder / Autoencoder Session
        let decoderSession = try await sessionStore.session(for: decoderPath.path) { path in
            try ORTSession(env: env, modelPath: path, sessionOptions: nil)
        }

        // Tokenize characters (Supertonic 3 uses UTF-8 bytes or raw character IDs)
        let utf8Bytes = Array(text.utf8)
        let inputIds = utf8Bytes.map { Int64($0) }
        let seqLen = inputIds.count

        let inputShape: [NSNumber] = [1, NSNumber(value: seqLen)]
        let inputData = Data(bytes: inputIds, count: seqLen * MemoryLayout<Int64>.stride)
        let inputVal = try ORTValue(tensorData: NSMutableData(data: inputData), elementType: .int64, shape: inputShape)

        // Run Text Encoder
        let encoderOutputs = try encoderSession.run(
            withInputs: ["input": inputVal],
            outputNames: try encoderSession.outputNames(),
            runOptions: nil
        )
        guard let encodedVal = encoderOutputs.values.first else {
            throw Error.inferenceFailed("Text encoder failed")
        }

        // Run Duration Predictor
        let durationOutputs = try durationSession.run(
            withInputs: ["input": encodedVal],
            outputNames: try durationSession.outputNames(),
            runOptions: nil
        )
        guard let durationVal = durationOutputs.values.first else {
            throw Error.inferenceFailed("Duration predictor failed")
        }

        // Run Decoder
        let decoderInputs: [String: ORTValue] = [
            "input": encodedVal,
            "duration": durationVal
        ]
        let decoderOutputs = try decoderSession.run(
            withInputs: decoderInputs,
            outputNames: try decoderSession.outputNames(),
            runOptions: nil
        )
        guard let audioOutputVal = decoderOutputs.values.first else {
            throw Error.inferenceFailed("Decoder failed")
        }

        let audioOutputData = try audioOutputVal.tensorDataWithError()
        let audioOutputFloats = ONNXTensorConverter.values(from: audioOutputData, as: Float.self)

        return AudioNormalizer.normalize(audioOutputFloats)
    }
    #else
    private func runInference(text: String, voice: VoiceModel, speakerId: Int, speed: Float) async throws -> [Float] {
        throw Error.runtimeUnavailable
    }
    #endif
}
