// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils
import AVFoundation

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

final class PocketTTSEngine: @unchecked Sendable, TTSEngine {
    enum Error: Swift.Error {
        case runtimeUnavailable
        case modelLoadFailed(String)
        case tokenizationFailed
        case inferenceFailed(String)
    }

    let type: TTSEngineType = .pocketTTS
    var playbackState: TTSPlaybackState {
        get async { state }
    }

    private var state: TTSPlaybackState = .stopped
    private let sessionStore = ONNXSessionStore()
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var continuation: CheckedContinuation<Void, Never>?

    // Model configuration parameters
    private var latentDim = 32
    private var conditioningDim = 1024
    private var sampleRate = 24000
    private var frameRate: Float = 12.5
    private var maxTokenPerChunk = 50
    private var insertBosBeforeVoice = true

    func play(text: String, voice: VoiceModel, speakerId: Int, speed: Float) async {
        guard ONNXRuntimeSupport.isAvailable else {
            Log.warning(type: .synthesizer, "PocketTTS requested, but ONNX Runtime is unavailable")
            return
        }

        Log.info(type: .synthesizer, "PocketTTS playback requested for voice \(voice.id), speakerId: \(speakerId), speed: \(speed)")
        state = .playing

        do {
            let samples = try await runInference(text: text, voice: voice, speakerId: speakerId, speed: speed)
            let rate = Double(sampleRate)

            stopPlayingAudio()

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)

            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
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
            Log.error("PocketTTS playback error: \(error)")
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

        Log.info(type: .synthesizer, "PocketTTS file synthesis requested to \(file), speed: \(speed)")

        let samples = try await runInference(text: text, voice: voice, speakerId: speakerId, speed: speed)
        let rate = Double(sampleRate)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
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
              let paths = FileManager.ModelPaths.installedModel(matching: modelInfo, engine: .pocketTTS),
              paths.exist,
              let folder = paths.modelFolder else {
            throw Error.modelLoadFailed("Missing model files or directory")
        }

        let bundlePath = folder.appendingPathComponent("bundle.json")
        let tokenizerPath = folder.appendingPathComponent("tokenizer.model")
        
        let textConditionerPath = folder.appendingPathComponent("text_conditioner.onnx")
        
        // Load main and flow models (try int8 first, fallback to fp32)
        let flowLmMains = ["flow_lm_main_int8.onnx", "flow_lm_main.onnx"]
        let flowLmMainPath = flowLmMains.map { folder.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
        
        let flowLmFlows = ["flow_lm_flow_int8.onnx", "flow_lm_flow.onnx"]
        let flowLmFlowPath = flowLmFlows.map { folder.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
        
        let mimiDecoders = ["mimi_decoder_int8.onnx", "mimi_decoder.onnx"]
        let mimiDecoderPath = mimiDecoders.map { folder.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }

        guard FileManager.default.fileExists(atPath: bundlePath.path),
              FileManager.default.fileExists(atPath: tokenizerPath.path),
              FileManager.default.fileExists(atPath: textConditionerPath.path),
              let mainPath = flowLmMainPath,
              let flowPath = flowLmFlowPath,
              let decoderPath = mimiDecoderPath else {
            throw Error.modelLoadFailed("Missing model files (bundle.json, tokenizer.model, etc.) under folder")
        }

        // 1. Read bundle.json for metadata
        let bundleData = try Data(contentsOf: bundlePath)
        let bundleDict = try JSONSerialization.jsonObject(with: bundleData) as? [String: Any]
        
        if let dim = bundleDict?["latent_dim"] as? Int { latentDim = dim }
        if let dim = bundleDict?["conditioning_dim"] as? Int { conditioningDim = dim }
        if let rate = bundleDict?["sample_rate"] as? Int { sampleRate = rate }
        if let fRate = bundleDict?["frame_rate"] as? Double { frameRate = Float(fRate) }
        if let val = bundleDict?["max_token_per_chunk"] as? Int { maxTokenPerChunk = val }
        if let bos = bundleDict?["insert_bos_before_voice"] as? Bool { insertBosBeforeVoice = bos }
        
        let flowStateManifest = (bundleDict?["flow_lm_state_manifest"] as? [[String: Any]]) ?? []
        let mimiStateManifest = (bundleDict?["mimi_state_manifest"] as? [[String: Any]]) ?? []

        // 2. Load Tokenizer
        let tokenizer = try SentencePieceTokenizer(modelPath: tokenizerPath)

        // 3. Load ONNX sessions
        let env = try ORTEnv(loggingLevel: .warning)
        let textConditioner = try await sessionStore.session(for: textConditionerPath.path) { path in
            try ORTSession(env: env, modelPath: path, sessionOptions: nil)
        }
        let flowLmMain = try await sessionStore.session(for: mainPath.path) { path in
            try ORTSession(env: env, modelPath: path, sessionOptions: nil)
        }
        let flowLmFlow = try await sessionStore.session(for: flowPath.path) { path in
            try ORTSession(env: env, modelPath: path, sessionOptions: nil)
        }
        let mimiDecoder = try await sessionStore.session(for: decoderPath.path) { path in
            try ORTSession(env: env, modelPath: path, sessionOptions: nil)
        }

        // 4. Load Voice Embedding
        let voiceEmbedding = try loadVoiceEmbedding(folder: folder, speakerId: speakerId)

        // 5. Preprocess text
        let preparedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preparedText.isEmpty else {
            throw Error.tokenizationFailed
        }

        // Split text into chunks (simulated for simplicity)
        let tokenIds = tokenizer.encode(text: preparedText)
        guard !tokenIds.isEmpty else {
            throw Error.tokenizationFailed
        }

        // 6. Text Conditioner Inference
        let tcInputShape: [NSNumber] = [1, NSNumber(value: tokenIds.count)]
        let tcInputData = Data(bytes: tokenIds.map { Int64($0) }, count: tokenIds.count * MemoryLayout<Int64>.stride)
        let tcInputVal = try ORTValue(tensorData: NSMutableData(data: tcInputData), elementType: .int64, shape: tcInputShape)
        
        let tcOutputs = try textConditioner.run(
            withInputs: ["token_ids": tcInputVal],
            outputNames: try textConditioner.outputNames(),
            runOptions: nil
        )
        guard let textEmbeddingsVal = tcOutputs.values.first else {
            throw Error.inferenceFailed("Text conditioner failed")
        }

        // 7. Prepare Voice conditioning
        var flowState = try initStates(manifest: flowStateManifest)
        let emptySeqShape: [NSNumber] = [1, 0, NSNumber(value: latentDim)]
        let emptySeqVal = try ORTValue(tensorData: NSMutableData(data: Data()), elementType: .float, shape: emptySeqShape)
        
        var mainInputs = ["sequence": emptySeqVal, "text_embeddings": textEmbeddingsVal]
        for (k, v) in flowState { mainInputs[k] = v }
        
        let mainOutputs = try flowLmMain.run(
            withInputs: mainInputs,
            outputNames: try flowLmMain.outputNames(),
            runOptions: nil
        )
        
        // Update states
        let mainOutputArray = Array(mainOutputs.values)
        updateStates(states: &flowState, outputs: mainOutputArray, manifest: flowStateManifest, offset: 2)

        // 8. Autoregressive frame generation loop
        var generatedLatents = [[Float]]()
        var currLatent = [Float](repeating: 0.0, count: latentDim)
        
        // Calculate max frames based on text length
        let maxFrames = Int(ceil((Float(tokenIds.count) / 3.0 + 2.0) * frameRate))
        let dt: Float = 1.0
        
        let emptyTextShape: [NSNumber] = [1, 0, NSNumber(value: conditioningDim)]
        let emptyTextVal = try ORTValue(tensorData: NSMutableData(data: Data()), elementType: .float, shape: emptyTextShape)

        let sVal = try ORTValue(tensorData: NSMutableData(data: Data(bytes: [Float(0.0)], count: 4)), elementType: .float, shape: [1, 1])
        let tVal = try ORTValue(tensorData: NSMutableData(data: Data(bytes: [Float(1.0)], count: 4)), elementType: .float, shape: [1, 1])

        var eosStep: Int?
        
        for step in 0..<maxFrames {
            let currShape: [NSNumber] = [1, 1, NSNumber(value: latentDim)]
            let currData = Data(bytes: currLatent, count: currLatent.count * MemoryLayout<Float>.stride)
            let currVal = try ORTValue(tensorData: NSMutableData(data: currData), elementType: .float, shape: currShape)

            var stepInputs = ["sequence": currVal, "text_embeddings": emptyTextVal]
            for (k, v) in flowState { stepInputs[k] = v }

            let stepOutputs = try flowLmMain.run(
                withInputs: stepInputs,
                outputNames: try flowLmMain.outputNames(),
                runOptions: nil
            )
            let stepOutputsArray = Array(stepOutputs.values)
            let conditioningVal = stepOutputsArray[0]
            let eosLogitVal = stepOutputsArray[1]
            updateStates(states: &flowState, outputs: stepOutputsArray, manifest: flowStateManifest, offset: 2)

            // Check EOS
            let eosData = try eosLogitVal.tensorDataWithError()
            let eosLogit = ONNXTensorConverter.values(from: eosData, as: Float.self).first ?? -10.0
            if eosLogit > -4.0 && eosStep == nil {
                eosStep = step
            }
            if let eos = eosStep, step >= eos + 3 {
                break
            }

            // Sample random normal x
            let std: Float = sqrt(0.7)
            var x = randomNormal(std: std)
            
            // Flow Model Euler Step
            let xShape: [NSNumber] = [1, NSNumber(value: latentDim)]
            let xData = Data(bytes: x, count: x.count * MemoryLayout<Float>.stride)
            let xVal = try ORTValue(tensorData: NSMutableData(data: xData), elementType: .float, shape: xShape)

            let flowOutputs = try flowLmFlow.run(
                withInputs: ["c": conditioningVal, "s": sVal, "t": tVal, "x": xVal],
                outputNames: try flowLmFlow.outputNames(),
                runOptions: nil
            )
            guard let flowVal = flowOutputs.values.first else {
                throw Error.inferenceFailed("Flow run failed")
            }
            let flowData = try flowVal.tensorDataWithError()
            let flowFloats = ONNXTensorConverter.values(from: flowData, as: Float.self)

            for i in 0..<latentDim {
                x[i] = x[i] + flowFloats[i] * dt
            }

            generatedLatents.append(x)
            currLatent = x
        }

        // 9. Decode latents using Mimi decoder
        var mimiState = try initStates(manifest: mimiStateManifest)
        var fullAudio = [Float]()
        
        let chunkSize = 15
        for idx in stride(from: 0, to: generatedLatents.count, by: chunkSize) {
            let endIdx = min(idx + chunkSize, generatedLatents.count)
            let chunk = Array(generatedLatents[idx..<endIdx])
            let flattened = chunk.flatMap { $0 }
            
            let chunkShape: [NSNumber] = [1, NSNumber(value: chunk.count), NSNumber(value: latentDim)]
            let chunkData = Data(bytes: flattened, count: flattened.count * MemoryLayout<Float>.stride)
            let chunkVal = try ORTValue(tensorData: NSMutableData(data: chunkData), elementType: .float, shape: chunkShape)

            var decInputs = ["latent": chunkVal]
            for (k, v) in mimiState { decInputs[k] = v }

            let decOutputs = try mimiDecoder.run(
                withInputs: decInputs,
                outputNames: try mimiDecoder.outputNames(),
                runOptions: nil
            )
            let decOutputsArray = Array(decOutputs.values)
            let audioVal = decOutputsArray[0]
            updateStates(states: &mimiState, outputs: decOutputsArray, manifest: mimiStateManifest, offset: 1)

            let audioData = try audioVal.tensorDataWithError()
            let audioFloats = ONNXTensorConverter.values(from: audioData, as: Float.self)
            fullAudio.append(contentsOf: audioFloats)
        }

        return AudioNormalizer.normalize(fullAudio)
    }

    private func loadVoiceEmbedding(folder: URL, speakerId: Int) throws -> [Float] {
        // Look for bos_before_voice.npy
        let bosFile = folder.appendingPathComponent("bos_before_voice.npy")
        if let parsed = NpyParser.parse(url: bosFile) {
            return parsed
        }
        
        // Fallback to random or zero embedding
        return [Float](repeating: 0.0, count: conditioningDim)
    }

    private func randomNormal(std: Float) -> [Float] {
        var values = [Float]()
        values.reserveCapacity(latentDim)
        for _ in 0..<latentDim {
            let u1 = Float.random(in: 0.0001...1.0)
            let u2 = Float.random(in: 0.0001...1.0)
            let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * Float.pi * u2)
            values.append(z0 * std)
        }
        return values
    }

    private func initStates(manifest: [[String: Any]]) throws -> [String: ORTValue] {
        var states = [String: ORTValue]()
        for entry in manifest {
            guard let inputName = entry["input_name"] as? String,
                  let shapeArray = entry["shape"] as? [Int],
                  let dtypeStr = entry["dtype"] as? String,
                  let fill = entry["fill"] as? String else {
                continue
            }
            
            let nsShape = shapeArray.map { NSNumber(value: $0) }
            let totalCount = shapeArray.reduce(1, *)
            
            if dtypeStr == "float32" {
                var buffer = [Float](repeating: 0.0, count: totalCount)
                if fill == "nan" {
                    buffer = [Float](repeating: Float.nan, count: totalCount)
                } else if fill == "ones" {
                    buffer = [Float](repeating: 1.0, count: totalCount)
                }
                
                let data = Data(bytes: buffer, count: buffer.count * 4)
                let val = try ORTValue(tensorData: NSMutableData(data: data), elementType: .float, shape: nsShape)
                states[inputName] = val
            } else if dtypeStr == "int64" {
                var buffer = [Int64](repeating: 0, count: totalCount)
                if fill == "ones" {
                    buffer = [Int64](repeating: 1, count: totalCount)
                }
                let data = Data(bytes: buffer, count: buffer.count * 8)
                let val = try ORTValue(tensorData: NSMutableData(data: data), elementType: .int64, shape: nsShape)
                states[inputName] = val
            } else if dtypeStr == "bool" {
                var buffer = [Bool](repeating: false, count: totalCount)
                if fill == "ones" {
                    buffer = [Bool](repeating: true, count: totalCount)
                }
                let bytes = buffer.map { UInt8($0 ? 1 : 0) }
                let data = Data(bytes)
                let val = try ORTValue(tensorData: NSMutableData(data: data), elementType: .bool, shape: nsShape)
                states[inputName] = val
            }
        }
        return states
    }

    private func updateStates(states: inout [String: ORTValue], outputs: [ORTValue], manifest: [[String: Any]], offset: Int) {
        for entry in manifest {
            guard let inputName = entry["input_name"] as? String,
                  let idx = entry["index"] as? Int else {
                continue
            }
            if offset + idx < outputs.count {
                states[inputName] = outputs[offset + idx]
            }
        }
    }
    #else
    private func runInference(text: String, voice: VoiceModel, speakerId: Int, speed: Float) async throws -> [Float] {
        throw Error.runtimeUnavailable
    }
    #endif
}

// MARK: - SentencePiece model Protobuf binary file parser
struct SentencePieceToken {
    let piece: String
    let score: Float
}

class SentencePieceModelParser {
    static func parse(data: Data) -> [SentencePieceToken] {
        var tokens: [SentencePieceToken] = []
        var idx = 0
        let totalLen = data.count
        
        func readVarint() -> Int? {
            var val = 0
            var shift = 0
            while idx < totalLen {
                let b = data[idx]
                val |= Int(b & 0x7F) << shift
                idx += 1
                if (b & 0x80) == 0 {
                    return val
                }
                shift += 7
            }
            return nil
        }
        
        while idx < totalLen {
            let tag = data[idx]
            let fieldNum = tag >> 3
            let wireType = tag & 0x07
            idx += 1
            
            if fieldNum == 1 && wireType == 2 {
                guard let length = readVarint() else { break }
                let endIdx = idx + length
                if endIdx > totalLen { break }
                
                var pieceStr = ""
                var scoreVal: Float = 0.0
                
                while idx < endIdx {
                    let subTag = data[idx]
                    let subField = subTag >> 3
                    let subWire = subTag & 0x07
                    idx += 1
                    
                    if subField == 1 && subWire == 2 {
                        guard let pLen = readVarint() else { break }
                        if idx + pLen > totalLen { break }
                        let subData = data[idx..<(idx+pLen)]
                        if let s = String(data: subData, encoding: .utf8) {
                            pieceStr = s
                        }
                        idx += pLen
                    } else if subField == 2 && subWire == 5 {
                        if idx + 4 > totalLen { break }
                        let fBytes = data[idx..<(idx+4)]
                        scoreVal = fBytes.withUnsafeBytes { $0.load(as: Float.self) }
                        idx += 4
                    } else {
                        if subWire == 0 {
                            _ = readVarint()
                        } else if subWire == 1 {
                            idx += 8
                        } else if subWire == 2 {
                            if let l = readVarint() {
                                idx += l
                            }
                        } else if subWire == 5 {
                            idx += 4
                        }
                    }
                }
                tokens.append(SentencePieceToken(piece: pieceStr, score: scoreVal))
                idx = endIdx
            } else {
                if wireType == 0 {
                    _ = readVarint()
                } else if wireType == 1 {
                    idx += 8
                } else if wireType == 2 {
                    if let l = readVarint() {
                        idx += l
                    }
                } else if wireType == 5 {
                    idx += 4
                }
            }
        }
        return tokens
    }
}

// MARK: - SentencePiece Unigram Tokenizer
class SentencePieceTokenizer {
    private var vocab: [String: (id: Int, score: Float)] = [:]
    private var unkId: Int = 0
    private var unkScore: Float = -20.0
    private var bosId: Int = 1
    private var eosId: Int = 2
    private var padId: Int = 3
    
    init(modelPath: URL) throws {
        let data = try Data(contentsOf: modelPath)
        let tokens = SentencePieceModelParser.parse(data: data)
        for (index, token) in tokens.enumerated() {
            vocab[token.piece] = (id: index, score: token.score)
            if token.piece == "<unk>" {
                unkId = index
                unkScore = token.score
            } else if token.piece == "<s>" {
                bosId = index
            } else if token.piece == "</s>" {
                eosId = index
            } else if token.piece == "<pad>" {
                padId = index
            }
        }
    }
    
    func encode(text: String) -> [Int] {
        let normalized = text.replacingOccurrences(of: " ", with: "\u{2581}")
        let chars = Array(normalized).map { String($0) }
        let N = chars.count
        guard N > 0 else { return [] }
        
        var dp = [Float](repeating: -Float.greatestFiniteMagnitude, count: N + 1)
        var backtrack = [Int](repeating: -1, count: N + 1)
        dp[0] = 0.0
        
        for i in 1...N {
            for j in 0..<i {
                let substr = chars[j..<i].joined()
                if let tokenInfo = vocab[substr] {
                    let score = tokenInfo.score
                    let totalScore = dp[j] + score
                    if totalScore > dp[i] {
                        dp[i] = totalScore
                        backtrack[i] = j
                    }
                }
            }
            if dp[i] == -Float.greatestFiniteMagnitude {
                dp[i] = dp[i - 1] + unkScore
                backtrack[i] = i - 1
            }
        }
        
        var path: [Int] = []
        var curr = N
        while curr > 0 {
            let start = backtrack[curr]
            if start == -1 { break }
            let substr = chars[start..<curr].joined()
            let tokenId = vocab[substr]?.id ?? unkId
            path.append(tokenId)
            curr = start
        }
        
        return path.reversed()
    }
}

// MARK: - NumPy .npy file parser
class NpyParser {
    static func parse(url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard data.count > 10, data[0] == 0x93, data[1] == 0x4E, data[2] == 0x55, data[3] == 0x4D, data[4] == 0x50, data[5] == 0x59 else {
            return nil
        }
        
        let major = data[6]
        
        var headerLen = 0
        if major == 1 {
            headerLen = Int(data[8]) | (Int(data[9]) << 8)
        } else if major == 2 {
            headerLen = Int(data[8]) | (Int(data[9]) << 8) | (Int(data[10]) << 16) | (Int(data[11]) << 24)
        }
        
        let headerOffset = major == 1 ? 10 : 12
        guard headerOffset + headerLen <= data.count else { return nil }
        
        let rawFloats = data.subdata(in: (headerOffset + headerLen)..<data.count)
        let floatCount = rawFloats.count / MemoryLayout<Float>.stride
        return rawFloats.withUnsafeBytes { rawBuffer in
            let typedPointer = rawBuffer.baseAddress!.assumingMemoryBound(to: Float.self)
            let typedBuffer = UnsafeBufferPointer(start: typedPointer, count: floatCount)
            return Array(typedBuffer)
        }
    }
}
