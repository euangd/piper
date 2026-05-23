// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import Combine
import PiperAppUtils

class ReaderHostModel: @unchecked Sendable, ObservableObject {
    @Published var viewModel: VoiceViewModel
    @Published var installedVoices: [VoiceModel] = []
    @Published var selectedVoice: VoiceModel?
    
    private var playingCancellable: AnyCancellable?
    let piper: PiperManager
    private let textImportService: TextImportService
    private let engines: EngineRegistry
    
    private var sentenceQueue: [String] = []
    private var currentSentenceIndex: Int = 0
    private var playbackTask: Task<Void, Never>?
    
    init(piper: PiperManager,
         textImportService: TextImportService = TextImportService(),
         engines: EngineRegistry = .shared) {
        self.piper = piper
        self.textImportService = textImportService
        self.engines = engines
        
        let voices = engines.installedVoices
        let defaultPaths = FileManager.ModelPaths.installedModels.first ?? FileManager.ModelPaths.engine
        
        self.viewModel = VoiceViewModel(
            paths: defaultPaths ?? FileManager.ModelPaths(model: URL(filePath: ""), json: URL(filePath: ""))!,
            modelInfo: defaultPaths?.info,
            demoText: "Import a website or text file to start reading."
        )
        
        self.installedVoices = voices
        self.selectedVoice = voices.first
        
        playingCancellable = piper.$isPlaying.sink { [weak self] isPlaying in
            guard let self = self else { return }
            self.viewModel.isPlaying = isPlaying
        }
    }
    
    deinit {
        playbackTask?.cancel()
        let piper = self.piper
        let engines = self.engines
        let voice = selectedVoice
        Task {
            if let voice = voice, let engine = engines.engine(for: voice) {
                await engine.stop()
            } else {
                await piper.stopPlaying()
            }
        }
    }
    
    func play() {
        guard let voice = selectedVoice,
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
            let speed = self.viewModel.speed
            
            if voice.engine == .piper {
                playbackTask = Task {
                    await MainActor.run {
                        self.viewModel.isPlaying = true
                        self.viewModel.isPaused = false
                        self.viewModel.playbackProgress = 0.0
                    }
                    await engine.play(text: demoText, voice: voice, speakerId: 0, speed: speed)
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
                        await engine.play(text: sentence, voice: voice, speakerId: 0, speed: speed)
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
        guard let voice = selectedVoice,
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
        guard let voice = selectedVoice,
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

    func stop() {
        Task {
            await stopPlayback()
        }
    }

    private func stopPlayback() async {
        playbackTask?.cancel()
        playbackTask = nil
        
        if let voice = selectedVoice,
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
                    self.viewModel.importError = error.localizedDescription
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
                    self.viewModel.importError = error.localizedDescription
                    self.viewModel.isImportingText = false
                }
            }
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
}
