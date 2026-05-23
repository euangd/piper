// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils
import AVFoundation

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

final class MeloTTSEngine: @unchecked Sendable, TTSEngine {
    enum Error: Swift.Error {
        case runtimeUnavailable
        case modelLoadFailed(String)
        case tokenizationFailed
        case inferenceFailed(String)
    }

    let type: TTSEngineType = .meloTTS
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
            Log.warning(type: .synthesizer, "MeloTTS requested, but ONNX Runtime is unavailable")
            return
        }

        Log.info(type: .synthesizer, "MeloTTS playback requested for voice \(voice.id), speakerId: \(speakerId), speed: \(speed)")
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
            Log.error("MeloTTS playback error: \(error)")
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

        Log.info(type: .synthesizer, "MeloTTS file synthesis requested to \(file), speed: \(speed)")

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
              let paths = FileManager.ModelPaths.installedModel(matching: modelInfo, engine: .meloTTS),
              paths.exist,
              let folder = paths.modelFolder else {
            throw Error.modelLoadFailed("Missing model files or directory")
        }

        let configPath = paths.json
        let bertPath = folder.appendingPathComponent("bert.onnx")
        let ttsPath = folder.appendingPathComponent("tts.onnx")
        let vocabPath = folder.appendingPathComponent("vocab.txt")
        let lexiconPath = folder.appendingPathComponent("lexicon.txt")

        // 1. Read config.json for symbols
        let configData = try Data(contentsOf: configPath)
        let configDict = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
        guard let symbols = configDict?["symbols"] as? [String] else {
            throw Error.modelLoadFailed("config.json is missing 'symbols'")
        }

        // 2. Load lexicon and tokenizer
        let tokenizer = try BertTokenizer(vocabPath: vocabPath)
        let g2p = EnglishG2P(lexiconPath: lexiconPath)

        // 3. Tokenize text into words & punctuation
        let rawTokens = Self.tokenizeToWordsAndPunctuation(text: text)

        // 4. Construct BERT input IDs and word2ph
        var bertInputIds = [Int32]()
        var phonesList = [String]()
        var word2ph = [Int]()

        // Prepend CLS token and SP phone
        if let clsId = tokenizer.vocab["[CLS]"] {
            bertInputIds.append(Int32(clsId))
        } else {
            bertInputIds.append(101)
        }
        phonesList.append("SP")
        word2ph.append(1)

        // Process each token
        for rawToken in rawTokens {
            let subTokens = tokenizer.wordpieceTokenize(word: rawToken)
            for (subIndex, subToken) in subTokens.enumerated() {
                let id = tokenizer.vocab[subToken] ?? tokenizer.vocab["[UNK]"] ?? 100
                bertInputIds.append(Int32(id))

                // Phonemes associated with the first sub-token only
                if subIndex == 0 {
                    let phonemes = g2p.phonemes(for: rawToken)
                    phonesList.append(contentsOf: phonemes)
                    word2ph.append(phonemes.count)
                } else {
                    word2ph.append(0)
                }
            }
        }

        // Append SEP token and SP phone
        if let sepId = tokenizer.vocab["[SEP]"] {
            bertInputIds.append(Int32(sepId))
        } else {
            bertInputIds.append(102)
        }
        phonesList.append("SP")
        word2ph.append(1)

        // 5. BERT Inference
        let env = try ORTEnv(loggingLevel: .warning)
        let bertSession = try await sessionStore.session(for: bertPath.path) { path in
            try ORTSession(env: env, modelPath: path, sessionOptions: nil)
        }

        let mask = [Int32](repeating: 1, count: bertInputIds.count)

        let bertInputShape: [NSNumber] = [1, NSNumber(value: bertInputIds.count)]
        let bertInputData = Data(bytes: bertInputIds, count: bertInputIds.count * MemoryLayout<Int32>.stride)
        let bertInputVal = try ORTValue(tensorData: NSMutableData(data: bertInputData), elementType: .int64, shape: bertInputShape)

        let maskData = Data(bytes: mask, count: mask.count * MemoryLayout<Int32>.stride)
        let maskVal = try ORTValue(tensorData: NSMutableData(data: maskData), elementType: .int64, shape: bertInputShape)

        let bertOutputs = try bertSession.run(
            withInputs: ["input_ids": bertInputVal, "attention_mask": maskVal],
            outputNames: try bertSession.outputNames(),
            runOptions: nil
        )

        guard let bertOutputVal = bertOutputs.values.first else {
            throw Error.inferenceFailed("BERT model run failed to produce outputs")
        }

        let bertOutputData = try bertOutputVal.tensorDataWithError()
        let bertOutputFloats = ONNXTensorConverter.values(from: bertOutputData, as: Float.self)

        let bertShape = try bertOutputVal.tensorTypeAndShapeInfo().shape
        let hiddenDim = bertShape.count >= 3 ? bertShape[2].intValue : 1024

        // 6. Align BERT features to phones
        let addBlank = true
        var finalPhones = phonesList
        var finalWord2ph = word2ph

        if addBlank {
            finalPhones = Self.intersperse(phonesList, with: "_")
            for i in 0..<finalWord2ph.count {
                finalWord2ph[i] = finalWord2ph[i] * 2
            }
            finalWord2ph[0] += 1
        }

        let alignedBert = Self.alignBertFeatures(bertOutput: bertOutputFloats, word2ph: finalWord2ph, hiddenDim: hiddenDim)
        let transposedBert = Self.transpose(flatArray: alignedBert, rows: finalPhones.count, cols: hiddenDim)

        // 7. TTS Inference
        let ttsSession = try await sessionStore.session(for: ttsPath.path) { path in
            try ORTSession(env: env, modelPath: path, sessionOptions: nil)
        }

        var symbolToId = [String: Int32]()
        for (idx, sym) in symbols.enumerated() {
            symbolToId[sym] = Int32(idx)
        }
        let padId = symbolToId["_"] ?? 0
        let unkId = symbolToId["UNK"] ?? padId
        let phoneIds = finalPhones.map { symbolToId[$0] ?? unkId }

        let ttsInputShape: [NSNumber] = [1, NSNumber(value: phoneIds.count)]
        let phoneIdsData = Data(bytes: phoneIds, count: phoneIds.count * MemoryLayout<Int32>.stride)
        let phoneIdsVal = try ORTValue(tensorData: NSMutableData(data: phoneIdsData), elementType: .int64, shape: ttsInputShape)

        let xLengths = [Int32(phoneIds.count)]
        let xLengthsData = Data(bytes: xLengths, count: xLengths.count * MemoryLayout<Int32>.stride)
        let xLengthsVal = try ORTValue(tensorData: NSMutableData(data: xLengthsData), elementType: .int64, shape: [1])

        let sid = [Int32(speakerId)]
        let sidData = Data(bytes: sid, count: sid.count * MemoryLayout<Int32>.stride)
        let sidVal = try ORTValue(tensorData: NSMutableData(data: sidData), elementType: .int64, shape: [1])

        let tones = [Int32](repeating: 0, count: phoneIds.count)
        let tonesData = Data(bytes: tones, count: tones.count * MemoryLayout<Int32>.stride)
        let tonesVal = try ORTValue(tensorData: NSMutableData(data: tonesData), elementType: .int64, shape: ttsInputShape)

        let bertFeaturesShape: [NSNumber] = [1, NSNumber(value: hiddenDim), NSNumber(value: phoneIds.count)]
        let bertFeaturesData = Data(bytes: transposedBert, count: transposedBert.count * MemoryLayout<Float>.stride)
        let bertFeaturesVal = try ORTValue(tensorData: NSMutableData(data: bertFeaturesData), elementType: .float, shape: bertFeaturesShape)

        let noiseScale: Float = 0.6
        let lengthScale: Float = 1.0 / speed
        let noiseScaleW: Float = 0.8
        let sdpRatio: Float = 0.2

        let float1Shape: [NSNumber] = [1]

        let nsVal = try ORTValue(tensorData: NSMutableData(data: Data(bytes: [noiseScale], count: 4)), elementType: .float, shape: float1Shape)
        let lsVal = try ORTValue(tensorData: NSMutableData(data: Data(bytes: [lengthScale], count: 4)), elementType: .float, shape: float1Shape)
        let nswVal = try ORTValue(tensorData: NSMutableData(data: Data(bytes: [noiseScaleW], count: 4)), elementType: .float, shape: float1Shape)
        let sdpVal = try ORTValue(tensorData: NSMutableData(data: Data(bytes: [sdpRatio], count: 4)), elementType: .float, shape: float1Shape)

        let ttsInputNames = try ttsSession.inputNames()
        var inputs = [String: ORTValue]()

        if ttsInputNames.contains("x") { inputs["x"] = phoneIdsVal }
        if ttsInputNames.contains("x_lengths") { inputs["x_lengths"] = xLengthsVal }
        if ttsInputNames.contains("sid") { inputs["sid"] = sidVal }
        if ttsInputNames.contains("tones") { inputs["tones"] = tonesVal }
        if ttsInputNames.contains("bert") { inputs["bert"] = bertFeaturesVal }
        if ttsInputNames.contains("noise_scale") { inputs["noise_scale"] = nsVal }
        if ttsInputNames.contains("length_scale") { inputs["length_scale"] = lsVal }
        if ttsInputNames.contains("noise_scale_w") { inputs["noise_scale_w"] = nswVal }
        if ttsInputNames.contains("sdp_ratio") { inputs["sdp_ratio"] = sdpVal }

        let ttsOutputs = try ttsSession.run(
            withInputs: inputs,
            outputNames: try ttsSession.outputNames(),
            runOptions: nil
        )

        guard let audioOutputVal = ttsOutputs.values.first else {
            throw Error.inferenceFailed("TTS model run failed to produce audio output")
        }

        let audioOutputData = try audioOutputVal.tensorDataWithError()
        let audioOutputFloats = ONNXTensorConverter.values(from: audioOutputData, as: Float.self)

        return AudioNormalizer.normalize(audioOutputFloats)
    }

    private static func tokenizeToWordsAndPunctuation(text: String) -> [String] {
        let punctuationSet = CharacterSet(charactersIn: "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~…")
        var result = [String]()
        let components = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        for component in components {
            var word = ""
            for char in component {
                let strChar = String(char)
                if strChar.rangeOfCharacter(from: punctuationSet) != nil {
                    if !word.isEmpty {
                        result.append(word)
                        word = ""
                    }
                    result.append(strChar)
                } else {
                    word.append(char)
                }
            }
            if !word.isEmpty {
                result.append(word)
            }
        }
        return result
    }

    private static func intersperse<T>(_ array: [T], with element: T) -> [T] {
        var result = [T]()
        result.reserveCapacity(array.count * 2 + 1)
        result.append(element)
        for item in array {
            result.append(item)
            result.append(element)
        }
        return result
    }

    private static func alignBertFeatures(bertOutput: [Float], word2ph: [Int], hiddenDim: Int) -> [Float] {
        var aligned = [Float]()
        let numTokens = word2ph.count
        aligned.reserveCapacity(numTokens * hiddenDim * 2)
        for i in 0..<numTokens {
            let repeatCount = word2ph[i]
            let offset = i * hiddenDim
            guard offset + hiddenDim <= bertOutput.count else { continue }
            let tokenFeature = bertOutput[offset..<(offset + hiddenDim)]
            for _ in 0..<repeatCount {
                aligned.append(contentsOf: tokenFeature)
            }
        }
        return aligned
    }

    private static func transpose(flatArray: [Float], rows: Int, cols: Int) -> [Float] {
        var transposed = [Float](repeating: 0, count: rows * cols)
        for r in 0..<rows {
            for c in 0..<cols {
                transposed[c * rows + r] = flatArray[r * cols + c]
            }
        }
        return transposed
    }
    #else
    private func runInference(text: String, voice: VoiceModel, speakerId: Int, speed: Float) async throws -> [Float] {
        throw Error.runtimeUnavailable
    }
    #endif
}

// MARK: - Helper Classes for Preprocessing

#if canImport(OnnxRuntimeBindings)
class BertTokenizer {
    let vocab: [String: Int]

    init(vocabPath: URL) throws {
        var tempVocab = [String: Int]()
        let content = try String(contentsOf: vocabPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                tempVocab[token] = index
            }
        }
        self.vocab = tempVocab
    }

    func wordpieceTokenize(word: String) -> [String] {
        let cleanWord = word.lowercased()
        if vocab[cleanWord] != nil {
            return [cleanWord]
        }

        var subTokens = [String]()
        var start = 0
        let chars = Array(cleanWord)

        while start < chars.count {
            var end = chars.count
            var curSubToken = ""
            var found = false

            while start < end {
                var substr = String(chars[start..<end])
                if start > 0 {
                    substr = "##" + substr
                }

                if vocab[substr] != nil {
                    curSubToken = substr
                    found = true
                    break
                }
                end -= 1
            }

            if !found {
                return ["[UNK]"]
            }

            subTokens.append(curSubToken)
            start = end
        }

        return subTokens
    }
}

class EnglishG2P {
    private var lexicon: [String: [String]] = [:]

    init(lexiconPath: URL) {
        if let content = try? String(contentsOf: lexiconPath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let word = parts[0].lowercased()
                    let phonemes = Array(parts[1...])
                    lexicon[word] = phonemes
                }
            }
        }
    }

    func phonemes(for word: String) -> [String] {
        let cleanWord = word.lowercased()
        if let ph = lexicon[cleanWord] {
            return ph
        }

        var ph = [String]()
        for char in cleanWord {
            switch char {
            case "a": ph.append(contentsOf: ["EY", "1"])
            case "b": ph.append(contentsOf: ["B", "IY", "1"])
            case "c": ph.append(contentsOf: ["S", "IY", "1"])
            case "d": ph.append(contentsOf: ["D", "IY", "1"])
            case "e": ph.append(contentsOf: ["IY", "1"])
            case "f": ph.append(contentsOf: ["EH", "F"])
            case "g": ph.append(contentsOf: ["JH", "IY", "1"])
            case "h": ph.append(contentsOf: ["EY", "CH"])
            case "i": ph.append(contentsOf: ["AY", "1"])
            case "j": ph.append(contentsOf: ["JH", "EY", "1"])
            case "k": ph.append(contentsOf: ["K", "EY", "1"])
            case "l": ph.append(contentsOf: ["EH", "L"])
            case "m": ph.append(contentsOf: ["EH", "M"])
            case "n": ph.append(contentsOf: ["EH", "N"])
            case "o": ph.append(contentsOf: ["OW", "1"])
            case "p": ph.append(contentsOf: ["P", "IY", "1"])
            case "q": ph.append(contentsOf: ["K", "YW", "1"])
            case "r": ph.append(contentsOf: ["AA", "R"])
            case "s": ph.append(contentsOf: ["EH", "S"])
            case "t": ph.append(contentsOf: ["T", "IY", "1"])
            case "u": ph.append(contentsOf: ["YW", "UW", "1"])
            case "v": ph.append(contentsOf: ["V", "IY", "1"])
            case "w": ph.append(contentsOf: ["D", "AH", "B", "AH", "L", "YW", "UW"])
            case "x": ph.append(contentsOf: ["EH", "K", "S"])
            case "y": ph.append(contentsOf: ["W", "AY", "1"])
            case "z": ph.append(contentsOf: ["Z", "IY", "1"])
            default: break
            }
        }
        return ph.isEmpty ? ["SP"] : ph
    }
}
#endif

