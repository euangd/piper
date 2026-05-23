// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils
import AVFoundation

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

final class KittenTTSEngine: @unchecked Sendable, TTSEngine {
    enum Error: Swift.Error {
        case runtimeUnavailable
        case modelLoadFailed(String)
        case tokenizationFailed
        case inferenceFailed(String)
    }

    let type: TTSEngineType = .kittenTTS
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
            Log.warning(type: .synthesizer, "KittenTTS requested, but ONNX Runtime is unavailable")
            return
        }

        Log.info(type: .synthesizer, "KittenTTS playback requested for voice \(voice.id), speakerId: \(speakerId), speed: \(speed)")
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
            Log.error("KittenTTS playback error: \(error)")
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

        Log.info(type: .synthesizer, "KittenTTS file synthesis requested to \(file), speed: \(speed)")

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
              let paths = FileManager.ModelPaths.installedModel(matching: modelInfo, engine: .kittenTTS),
              paths.exist,
              let folder = paths.modelFolder else {
            throw Error.modelLoadFailed("Missing model files or directory")
        }

        let configPath = paths.json
        let modelPath = paths.model
        let tokenizerPath = folder.appendingPathComponent("tokenizer.json")

        // 1. Read tokenizer.json for vocab
        guard FileManager.default.fileExists(atPath: tokenizerPath.path) else {
            throw Error.modelLoadFailed("tokenizer.json is missing in model folder")
        }
        let tokenizerData = try Data(contentsOf: tokenizerPath)
        let tokenizerDict = try JSONSerialization.jsonObject(with: tokenizerData) as? [String: Any]
        guard let modelDict = tokenizerDict?["model"] as? [String: Any],
              let vocab = modelDict["vocab"] as? [String: Int] else {
            throw Error.modelLoadFailed("tokenizer.json is missing 'model.vocab' mapping")
        }

        // 2. Load G2P
        let g2p = KittenG2P(modelFolder: folder)

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

        // 6. Load voice style embedding
        let styleEmbedding = try loadVoiceEmbedding(folder: folder, speakerId: speakerId)

        // 7. Bind inputs dynamically
        let inputNames = try session.inputNames()
        var inputs = [String: ORTValue]()

        // Bind token ids
        let tokenIdsShape: [NSNumber] = [1, NSNumber(value: inputIds.count)]
        let tokenIdsData = Data(bytes: inputIds, count: inputIds.count * MemoryLayout<Int64>.stride)
        let tokenIdsVal = try ORTValue(tensorData: NSMutableData(data: tokenIdsData), elementType: .int64, shape: tokenIdsShape)

        if inputNames.contains("input_ids") {
            inputs["input_ids"] = tokenIdsVal
        } else if inputNames.contains("tokens") {
            inputs["tokens"] = tokenIdsVal
        }

        // Bind style embedding
        var matchedStyleName: String?
        if inputNames.contains("style") { matchedStyleName = "style" }
        else if inputNames.contains("style_vector") { matchedStyleName = "style_vector" }

        if let styleName = matchedStyleName {
            var styleShape: [NSNumber] = [1, NSNumber(value: styleEmbedding.count)]
            if let info = try? session.inputTypeAndShapeInfo(forInputName: styleName) {
                let shape = info.shape
                styleShape = shape.map { num in
                    let val = num.intValue
                    return val <= 0 ? 1 : num
                }
                if styleShape.count > 0 {
                    let total = styleShape.reduce(1) { $0 * $1.intValue }
                    if total != styleEmbedding.count {
                        styleShape[styleShape.count - 1] = NSNumber(value: styleEmbedding.count / (total / styleShape.last!.intValue))
                    }
                }
            }
            let styleData = Data(bytes: styleEmbedding, count: styleEmbedding.count * MemoryLayout<Float>.stride)
            let styleVal = try ORTValue(tensorData: NSMutableData(data: styleData), elementType: .float, shape: styleShape)
            inputs[styleName] = styleVal
        }

        // Bind speed
        if inputNames.contains("speed") {
            let speedVal = try ORTValue(tensorData: NSMutableData(data: Data(bytes: [speed], count: 4)), elementType: .float, shape: [1])
            inputs["speed"] = speedVal
        }

        // 8. Run ONNX inference
        let outputs = try session.run(
            withInputs: inputs,
            outputNames: try session.outputNames(),
            runOptions: nil
        )

        guard let audioOutputVal = outputs.values.first else {
            throw Error.inferenceFailed("KittenTTS model run failed to produce audio output")
        }

        let audioOutputData = try audioOutputVal.tensorDataWithError()
        let audioOutputFloats = ONNXTensorConverter.values(from: audioOutputData, as: Float.self)

        return AudioNormalizer.normalize(audioOutputFloats)
    }

    private func loadVoiceEmbedding(folder: URL, speakerId: Int) throws -> [Float] {
        let voicesFolder = folder.appendingPathComponent("voices")
        let fileManager = FileManager.default
        var voiceFiles: [URL] = []
        if fileManager.fileExists(atPath: voicesFolder.path) {
            let files = try fileManager.contentsOfDirectory(at: voicesFolder, includingPropertiesForKeys: nil)
            voiceFiles = files.filter { $0.pathExtension == "bin" }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        }

        if voiceFiles.isEmpty {
            let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            voiceFiles = files.filter { $0.pathExtension == "bin" }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        }

        guard !voiceFiles.isEmpty else {
            throw Error.modelLoadFailed("No voice embedding (.bin) files found in voices folder or root")
        }

        let selectedURL = voiceFiles[speakerId % voiceFiles.count]
        Log.info(type: .synthesizer, "KittenTTS selected voice file: \(selectedURL.lastPathComponent)")

        let data = try Data(contentsOf: selectedURL)
        let floatCount = data.count / MemoryLayout<Float>.stride
        return data.withUnsafeBytes { rawBuffer in
            let typedPointer = rawBuffer.baseAddress!.assumingMemoryBound(to: Float.self)
            let typedBuffer = UnsafeBufferPointer(start: typedPointer, count: floatCount)
            return Array(typedBuffer)
        }
    }
    #else
    private func runInference(text: String, voice: VoiceModel, speakerId: Int, speed: Float) async throws -> [Float] {
        throw Error.runtimeUnavailable
    }
    #endif
}

// MARK: - Helper G2P class for KittenTTS
class KittenG2P {
    private var lexicon: [String: String] = [:]

    init(modelFolder: URL) {
        let localLexicon = modelFolder.appendingPathComponent("lexicon.txt")
        if FileManager.default.fileExists(atPath: localLexicon.path) {
            loadLexicon(from: localLexicon)
            return
        }

        // Re-use other models' lexicons if available
        for paths in FileManager.ModelPaths.installedModels {
            if let folder = paths.modelFolder {
                let candidate = folder.appendingPathComponent("lexicon.txt")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    loadLexicon(from: candidate)
                    if !lexicon.isEmpty { return }
                }
            }
        }
    }

    private func loadLexicon(from url: URL) {
        if let content = try? String(contentsOf: url, encoding: .utf8) {
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
