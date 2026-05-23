// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import Combine
import PiperAppUtils
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

class VoiceHostModel: @unchecked Sendable, ObservableObject {
    @Published var viewModel: VoiceViewModel
    private var playingCancellable: AnyCancellable?
    let piper: PiperManager
    private let textImportService: TextImportService
    private let engines: EngineRegistry
    weak var delegate: ModelChangeDelegate?
    private var sentenceQueue: [String] = []
    private var currentSentenceIndex: Int = 0
    private var playbackTask: Task<Void, Never>?
    
    init(piper: PiperManager,
         modelPaths: FileManager.ModelPaths,
         textImportService: TextImportService = TextImportService(),
         engines: EngineRegistry = .shared,
         delegate: ModelChangeDelegate?) {
        self.piper = piper
        self.textImportService = textImportService
        self.engines = engines
        viewModel = VoiceViewModel(paths: modelPaths,
                                   modelInfo: modelPaths.info)
        self.delegate = delegate
        updateSample()
        playingCancellable = piper.$isPlaying.sink { [weak self] isPlaying in
            guard let self = self else {
                return
            }
            self.viewModel.isPlaying = isPlaying
        }
    }
    
    deinit {
        playbackTask?.cancel()
        let piper = self.piper
        let engines = self.engines
        let voice = voiceModel
        Task {
            if let voice = voice, let engine = engines.engine(for: voice) {
                await engine.stop()
            } else {
                await piper.stopPlaying()
            }
        }
    }
    
    func updateSample() {
        guard let sampleJSONData = NSDataAsset(name: "Samples")?.data else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let samples = try decoder.decode([String: String].self, from: sampleJSONData)
            if  let code = viewModel.paths.info?.language.code,
                let sample = samples[code] {
                viewModel.demoText = sample
            }
        } catch {
            Log.error("Failed to decode samples: \(error)")
        }
    }
    
    func uninstall() {
        Task {
            await stopPlayback()
        }
        piper.unstall(paths: viewModel.paths)
        delegate?.modelDidChange()
    }
    
    func play() {
        guard let voice = voiceModel,
              let engine = engines.engine(for: voice) else {
            return
        }
        
        let isPlaying = self.viewModel.isPlaying
        let isPaused = self.viewModel.isPaused
        
        if isPlaying {
            if isPaused {
                resume()
            } else {
                pause()
            }
        } else {
            let demoText = viewModel.demoText
            let speakerId = self.viewModel.selectedSpeaker
            let speed = self.viewModel.speed
            
            if voice.engine == .piper {
                playbackTask = Task {
                    await MainActor.run {
                        self.viewModel.isPlaying = true
                        self.viewModel.isPaused = false
                        self.viewModel.playbackProgress = 0.0
                    }
                    await engine.play(text: demoText, voice: voice, speakerId: speakerId, speed: speed)
                    await MainActor.run {
                        self.viewModel.isPlaying = false
                        self.viewModel.isPaused = false
                    }
                }
            } else {
                sentenceQueue = splitTextIntoSentences(demoText)
                currentSentenceIndex = 0
                
                playbackTask = Task {
                    await MainActor.run {
                        self.viewModel.isPlaying = true
                        self.viewModel.isPaused = false
                        self.viewModel.playbackProgress = 0.0
                    }
                    
                    for idx in 0..<sentenceQueue.count {
                        if Task.isCancelled { break }
                        
                        await MainActor.run {
                            self.currentSentenceIndex = idx
                            self.updateProgress()
                        }
                        
                        let sentence = sentenceQueue[idx]
                        await engine.play(text: sentence, voice: voice, speakerId: speakerId, speed: speed)
                    }
                    
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.viewModel.isPlaying = false
                            self.viewModel.isPaused = false
                            self.viewModel.playbackProgress = 1.0
                            self.viewModel.timeRemaining = ""
                            self.viewModel.elapsedTime = ""
                        }
                    }
                }
            }
        }
    }
    
    func pause() {
        guard let voice = voiceModel,
              let engine = engines.engine(for: voice) else {
            return
        }
        Task {
            await engine.pause()
            await MainActor.run {
                self.viewModel.isPaused = true
            }
        }
    }
    
    func resume() {
        guard let voice = voiceModel,
              let engine = engines.engine(for: voice) else {
            return
        }
        Task {
            await engine.resume()
            await MainActor.run {
                self.viewModel.isPaused = false
            }
        }
    }

    private var voiceModel: VoiceModel? {
        guard let modelInfo = viewModel.modelInfo else {
            return nil
        }
        return VoiceModel(engine: viewModel.paths.engine, info: modelInfo)
    }

    func stop() {
        Task {
            await stopPlayback()
        }
    }

    private func stopPlayback() async {
        playbackTask?.cancel()
        playbackTask = nil
        
        if let voice = voiceModel,
           let engine = engines.engine(for: voice) {
            await engine.stop()
        } else {
            await piper.stopPlaying()
        }

        await MainActor.run {
            self.viewModel.isPlaying = false
            self.viewModel.isPaused = false
            self.viewModel.playbackProgress = 0.0
            self.viewModel.timeRemaining = ""
            self.viewModel.elapsedTime = ""
        }
    }
    
    private func splitTextIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let pattern = "[^.!?\\n\\r]+[.!?\\n\\r]*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [text]
        }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        for result in results {
            let sentence = nsString.substring(with: result.range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        if sentences.isEmpty && !text.isEmpty {
            sentences.append(text)
        }
        return sentences
    }
    
    private func updateProgress() {
        guard !sentenceQueue.isEmpty else { return }
        
        let totalChars = sentenceQueue.map { $0.count }.reduce(0, +)
        guard totalChars > 0 else { return }
        
        var processedChars = 0
        for i in 0..<currentSentenceIndex {
            processedChars += sentenceQueue[i].count
        }
        
        let progress = Float(processedChars) / Float(totalChars)
        viewModel.playbackProgress = progress
        
        let charsPerSecond = 12.0 * Double(viewModel.speed)
        let elapsed = Double(processedChars) / charsPerSecond
        let remaining = Double(totalChars - processedChars) / charsPerSecond
        
        viewModel.elapsedTime = formatTime(elapsed)
        viewModel.timeRemaining = "-" + formatTime(remaining)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    func importWebsite(_ urlString: String) {
        Task { [weak self] in
            guard let self else { return }

            await MainActor.run {
                self.viewModel.isImportingText = true
                self.viewModel.importError = nil
            }

            do {
                let text = try await textImportService.importWebsite(from: urlString)
                await MainActor.run {
                    self.viewModel.demoText = text
                    self.viewModel.isImportingText = false
                }
            } catch {
                await MainActor.run {
                    self.viewModel.importError = error.humanReadableImportError
                    self.viewModel.isImportingText = false
                }
            }
        }
    }

    func importTextFile(_ url: URL) {
        Task { [weak self] in
            guard let self else { return }

            await MainActor.run {
                self.viewModel.isImportingText = true
                self.viewModel.importError = nil
            }

            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let text = try textImportService.importFile(from: url)
                await MainActor.run {
                    self.viewModel.demoText = text
                    self.viewModel.isImportingText = false
                }
            } catch {
                await MainActor.run {
                    self.viewModel.importError = error.humanReadableImportError
                    self.viewModel.isImportingText = false
                }
            }
        }
    }
}

extension VoiceHostModel: VoiceFileSyntehesizer {
    
    enum Error: Swift.Error {
        case modelIsNotAvailable
        case engineIsNotAvailable
    }
    
    var fileName: String {
        guard let modelInfo = viewModel.modelInfo else {
           return UUID().uuidString
        }
        return "\(modelInfo.name)_\(Int.random(in: 0...10000))"
    }
    
    func syntehesize(text: String, to file: String) async throws {
        guard let voice = voiceModel else {
            throw Error.modelIsNotAvailable
        }

        guard let engine = engines.engine(for: voice) else {
            throw Error.engineIsNotAvailable
        }

        try await engine.synthesize(text: text,
                                    to: file,
                                    voice: voice,
                                    speakerId: self.viewModel.selectedSpeaker,
                                    speed: self.viewModel.speed)
    }
}

private extension Error {
    var humanReadableImportError: String {
        if let importError = self as? TextImportService.ImportError {
            switch importError {
            case .invalidURL:
                return "Enter a valid website URL."
            case .unsupportedFileType:
                return "This file type is not supported."
            case .emptyContent:
                return "No readable text was found."
            }
        }

        return localizedDescription
    }
}
