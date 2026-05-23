// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils
import AVFoundation

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

final class KokoroTTSEngine: @unchecked Sendable, TTSEngine {
    enum Error: Swift.Error {
        case runtimeUnavailable
        case modelLoadFailed(String)
        case tokenizationFailed
        case inferenceFailed(String)
    }

    let type: TTSEngineType = .kokoro
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
            Log.warning(type: .synthesizer, "Kokoro requested, but ONNX Runtime is unavailable")
            return
        }

        Log.info(type: .synthesizer, "Kokoro playback requested for voice \(voice.id), speakerId: \(speakerId), speed: \(speed)")
        state = .playing

        do {
            let samples = try await runInference(text: text, voice: voice, speakerId: speakerId, speed: speed)
            let sampleRate = voice.info?.audio.sampleRate ?? 24000.0

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
            Log.error("Kokoro playback error: \(error)")
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

        Log.info(type: .synthesizer, "Kokoro file synthesis requested to \(file), speed: \(speed)")

        let samples = try await runInference(text: text, voice: voice, speakerId: speakerId, speed: speed)
        let sampleRate = voice.info?.audio.sampleRate ?? 24000.0

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
              let paths = FileManager.ModelPaths.installedModel(matching: modelInfo, engine: .kokoro),
              paths.exist,
              let folder = paths.modelFolder else {
            throw Error.modelLoadFailed("Missing model files or directory")
        }

        let configPath = paths.json
        let modelPath = paths.model
        let lexiconPath = folder.appendingPathComponent("lexicon.txt")

        // 1. Read config.json for vocab
        let configData = try Data(contentsOf: configPath)
        let configDict = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
        guard let vocab = configDict?["vocab"] as? [String: Int] else {
            throw Error.modelLoadFailed("config.json is missing 'vocab' mapping")
        }

        // 2. Load lexicon
        let g2p = KokoroG2P(lexiconPath: lexiconPath)

        // 3. Clean text and convert to phoneme characters
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var phonemeString = ""
        for (i, word) in words.enumerated() {
            if i > 0 { phonemeString += " " }
            phonemeString += g2p.phonemes(for: word)
        }

        // 4. Construct input IDs (prepending/appending pad ID 0)
        var inputIds = [Int64]()
        inputIds.append(0) // pad

        for char in phonemeString {
            let strChar = String(char)
            if let id = vocab[strChar] {
                inputIds.append(Int64(id))
            }
        }
        inputIds.append(0) // pad

        // 5. Load model session
        let env = try ORTEnv(loggingLevel: .warning)
        let session = try await sessionStore.session(for: modelPath.path) { path in
            try ORTSession(env: env, modelPath: path, sessionOptions: nil)
        }

        // 6. Determine padding size
        var seqLen = 128
        let inputNames = try session.inputNames()
        if inputIds.count > seqLen {
            inputIds = Array(inputIds[0..<seqLen])
        } else {
            inputIds.append(contentsOf: [Int64](repeating: 0, count: seqLen - inputIds.count))
        }

        let attentionMask = inputIds.map { $0 > 0 ? Int64(1) : Int64(0) }

        // 7. Load voice style embedding
        let styleEmbedding = try loadStyleVector(folder: folder, speakerId: speakerId)

        // 8. Run ONNX inference
        let inputShape: [NSNumber] = [1, NSNumber(value: seqLen)]
        
        let inputIdsData = Data(bytes: inputIds, count: inputIds.count * MemoryLayout<Int64>.stride)
        let inputIdsVal = try ORTValue(tensorData: NSMutableData(data: inputIdsData), elementType: .int64, shape: inputShape)

        let maskData = Data(bytes: attentionMask, count: attentionMask.count * MemoryLayout<Int64>.stride)
        let maskVal = try ORTValue(tensorData: NSMutableData(data: maskData), elementType: .int64, shape: inputShape)

        // Shape style vector: typically [1, 1, 256] or [1, 256]
        var styleShape: [NSNumber] = [1, 1, 256]
        // We can check expected shape dynamically if needed, default to [1, 1, 256]
        let styleData = Data(bytes: styleEmbedding, count: styleEmbedding.count * MemoryLayout<Float>.stride)
        let styleVal = try ORTValue(tensorData: NSMutableData(data: styleData), elementType: .float, shape: styleShape)

        let speedVal = try ORTValue(tensorData: NSMutableData(data: Data(bytes: [speed], count: 4)), elementType: .float, shape: [1])

        var inputs = [String: ORTValue]()
        if inputNames.contains("input_ids") { inputs["input_ids"] = inputIdsVal }
        if inputNames.contains("attention_mask") { inputs["attention_mask"] = maskVal }
        if inputNames.contains("style") { inputs["style"] = styleVal }
        if inputNames.contains("speed") { inputs["speed"] = speedVal }

        let outputs = try session.run(
            withInputs: inputs,
            outputNames: try session.outputNames(),
            runOptions: nil
        )

        guard let audioOutputVal = outputs.values.first else {
            throw Error.inferenceFailed("Kokoro model run failed to produce audio output")
        }

        let audioOutputData = try audioOutputVal.tensorDataWithError()
        let audioOutputFloats = ONNXTensorConverter.values(from: audioOutputData, as: Float.self)

        return AudioNormalizer.normalize(audioOutputFloats)
    }

    private func loadStyleVector(folder: URL, speakerId: Int) throws -> [Float] {
        let specificStyleURL = folder.appendingPathComponent("style_\(speakerId).bin")
        let defaultStyleURL = folder.appendingPathComponent("style.bin")
        let styleURL = FileManager.default.fileExists(atPath: specificStyleURL.path) ? specificStyleURL : defaultStyleURL

        guard FileManager.default.fileExists(atPath: styleURL.path) else {
            return [Float](repeating: 0.0, count: 256)
        }

        let data = try Data(contentsOf: styleURL)
        let floatCount = data.count / MemoryLayout<Float>.stride
        guard floatCount >= 256 else {
            throw Error.modelLoadFailed("Style file is too small (\(floatCount) floats)")
        }

        return data.withUnsafeBytes { rawBuffer in
            let typedPointer = rawBuffer.baseAddress!.assumingMemoryBound(to: Float.self)
            let typedBuffer = UnsafeBufferPointer(start: typedPointer, count: 256)
            return Array(typedBuffer)
        }
    }
    #else
    private func runInference(text: String, voice: VoiceModel, speakerId: Int, speed: Float) async throws -> [Float] {
        throw Error.runtimeUnavailable
    }
    #endif
}

// MARK: - Helper Classes for Kokoro Preprocessing

#if canImport(OnnxRuntimeBindings)
class KokoroG2P {
    private var lexicon: [String: String] = [:]

    init(lexiconPath: URL) {
        if let content = try? String(contentsOf: lexiconPath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let word = parts[0].lowercased()
                    let phonemeString = parts[1]
                    lexicon[word] = phonemeString
                }
            }
        }
    }

    func phonemes(for word: String) -> String {
        let cleanWord = word.lowercased()
        if let ph = lexicon[cleanWord] {
            return ph
        }

        var ph = ""
        for char in cleanWord {
            switch char {
            case "a": ph += "eɪ"
            case "b": ph += "bi"
            case "c": ph += "si"
            case "d": ph += "di"
            case "e": ph += "i"
            case "f": ph += "ef"
            case "g": ph += "dʒi"
            case "h": ph += "eɪtʃ"
            case "i": ph += "aɪ"
            case "j": ph += "dʒeɪ"
            case "k": ph += "keɪ"
            case "l": ph += "el"
            case "m": ph += "em"
            case "n": ph += "en"
            case "o": ph += "oʊ"
            case "p": ph += "pi"
            case "q": ph += "kju"
            case "r": ph += "ɑː"
            case "s": ph += "es"
            case "t": ph += "ti"
            case "u": ph += "ju"
            case "v": ph += "vi"
            case "w": ph += "dʌbəlju"
            case "x": ph += "eks"
            case "y": ph += "waɪ"
            case "z": ph += "zi"
            default: break
            }
        }
        return ph.isEmpty ? " " : ph
    }
}
#endif
