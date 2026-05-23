// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

enum DownloadEvent {
    case progress(Double)
    case finished(FileManager.ModelPaths)
}

protocol VoiceLoadListener: AnyObject {
    func progressUpdated(_ progress: Float)
}

class VoiceLoader: NSObject {
    private enum Error: Swift.Error {
        case nilURL
        case loadingFailed
        case checksumMismatch
    }

    private enum Constants {
        static let baseURL = "https://huggingface.co/IhorShevchuk/piper1-voices-fp16-quantized/resolve/main"
        static let sampesBaseURL = "https://rhasspy.github.io/piper-samples/samples"

        static var voicesURL: URL? {
            URL(string: "\(Constants.baseURL)/voices.json")
        }
    }

    private var continuations: [Int: CheckedContinuation<URL, Swift.Error>] = [:]
    private var observations: [Int: NSKeyValueObservation] = [:]

    private lazy var operationQueue: OperationQueue = {
        OperationQueue()
    }()

    private lazy var urlSession: URLSession = {
        URLSession(configuration: .default,
                   delegate: self,
                   delegateQueue: operationQueue)
    }()

    private func load<Item: Decodable>(url: URL?) async throws -> Item {
        guard let url else {
            throw Error.nilURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        return try decoder.decode(Item.self, from: data)
    }

    func loadVoices() async throws -> [Voice] {
        let bundleCandidates: [URL?] = [
            Bundle.main.url(forResource: "huggingface_piper_en", withExtension: "json"),
            Bundle.main.url(forResource: "voices_english_manifest", withExtension: "json"),
            Bundle.main.url(forResource: "huggingface_piper_en", withExtension: "json", subdirectory: "manifests"),
            Bundle.main.resourceURL?.appendingPathComponent("manifests/huggingface_piper_en.json")
        ]

        for candidate in bundleCandidates {
            if let local = candidate {
                do {
                    let data = try Data(contentsOf: local)
                    let decoder = JSONDecoder()
                    let allVoices = try decoder.decode([String: Voice].self, from: data)
                    return try mergedWithExternalCatalog(Array(allVoices.values), decoder: decoder)
                } catch {
                    Log.debug("Failed to load local voices manifest at \(local): \(error). Trying next candidate.")
                }
            }
        }

        let allVoices: [String: Voice] = try await load(url: Constants.voicesURL)
        let englishOnly = allVoices.values.filter { voice in
            voice.language.family.lowercased() == "en" || voice.language.code.lowercased().hasPrefix("en")
        }
        return try mergedWithExternalCatalog(Array(englishOnly), decoder: JSONDecoder())
    }

    func sampleURL(for voice: Voice, speaker: String = "0") -> URL? {
        guard voice.engine == .piper else {
            return nil
        }
        let languageCode = voice.language.code
        let languageFamily = languageCode.split(separator: "_").first.map(String.init) ?? languageCode
        let path = "\(languageFamily)/\(languageCode)/\(voice.name)/\(voice.quality)/speaker_\(speaker).mp3"
        return URL(string: "\(Constants.sampesBaseURL)/\(path)")
    }

    func download(voice: Voice) -> AsyncThrowingStream<DownloadEvent, Swift.Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let modelPath = voice.modelPath,
                          let jsonPath = voice.jsonPath else {
                        throw Error.loadingFailed
                    }

                    func resolve(_ path: String) -> URL? {
                        if let url = URL(string: path), url.scheme != nil {
                            return url
                        }
                        return URL(string: "\(Constants.baseURL)/\(path)")
                    }

                    let bundleFolder = try createTemporaryBundleFolder()
                    let totalBytes = max(voice.files.values.reduce(0) { $0 + $1.size_bytes }, 1)
                    var baseProgress = 0.0
                    var downloadedFiles: [String: URL] = [:]

                    for (path, file) in voice.files.sorted(by: { $0.key < $1.key }) {
                        guard let url = file.url.flatMap(URL.init(string:)) ?? resolve(path) else {
                            throw Error.nilURL
                        }

                        let weight = Double(file.size_bytes) / Double(totalBytes)
                        let temporaryFile = try await downloadFile(
                            from: url,
                            weight: weight,
                            baseProgress: baseProgress,
                            expectedMD5: file.md5_digest,
                            continuation: continuation
                        )
                        baseProgress += weight

                        let localFile = bundleFolder.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
                        try? FileManager.default.removeItem(at: localFile)
                        try FileManager.default.copyItem(at: temporaryFile, to: localFile)
                        try? FileManager.default.removeItem(at: temporaryFile)
                        downloadedFiles[path] = localFile
                    }

                    let jsonLocalURL: URL?
                    if voice.engine == .piper {
                        jsonLocalURL = downloadedFiles[jsonPath]
                    } else {
                        jsonLocalURL = try createInstalledMetadata(for: voice, in: bundleFolder)
                    }

                    guard let jsonLocalURL,
                          let modelLocalURL = downloadedFiles[modelPath],
                          let paths = FileManager.ModelPaths(model: modelLocalURL,
                                                             json: jsonLocalURL,
                                                             engine: voice.engine) else {
                        throw Error.loadingFailed
                    }

                    continuation.yield(.finished(paths))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func mergedWithExternalCatalog(_ voices: [Voice], decoder: JSONDecoder) throws -> [Voice] {
        let catalogCandidates: [URL?] = [
            Bundle.main.url(forResource: "external_tts_manifest", withExtension: "json"),
            Bundle.main.url(forResource: "external_tts_manifest", withExtension: "json", subdirectory: "manifests"),
            Bundle.main.resourceURL?.appendingPathComponent("manifests/external_tts_manifest.json")
        ]

        for candidate in catalogCandidates {
            guard let local = candidate else {
                continue
            }
            do {
                let data = try Data(contentsOf: local)
                let externalVoices = try decoder.decode([String: Voice].self, from: data)
                return voices + Array(externalVoices.values)
            } catch {
                Log.debug("Failed to load external model catalog at \(local): \(error). Trying next candidate.")
            }
        }

        return voices
    }

    private func createTemporaryBundleFolder() throws -> URL {
        guard let temporaryDirectoryURL = FileManager.tempFolderInDocumentDirectory else {
            throw FileManager.Error.nilTemporaryDirectory
        }
        let folder = temporaryDirectoryURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func createInstalledMetadata(for voice: Voice, in folder: URL) throws -> URL {
        let metadataURL = folder.appendingPathComponent("installed-model-info.json")
        let sampleRate: Double
        switch voice.engine {
        case .meloTTS:
            sampleRate = 44100.0
        case .kokoro:
            sampleRate = 24000.0
        default:
            sampleRate = 24000.0
        }
        let metadata: [String: Any] = [
            "dataset": voice.name,
            "piper_version": voice.engine.rawValue,
            "language": [
                "code": voice.language.code,
                "family": voice.language.family,
                "region": voice.language.region
            ],
            "audio": [
                "sample_rate": sampleRate,
                "quality": voice.quality
            ],
            "speaker_id_map": [:],
            "num_speakers": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: metadataURL)
        return metadataURL
    }

    private func downloadFile(
        from url: URL,
        weight: Double,
        baseProgress: Double,
        expectedMD5: String? = nil,
        continuation: AsyncThrowingStream<DownloadEvent, Swift.Error>.Continuation
    ) async throws -> URL {
        let task = urlSession.downloadTask(with: url)
        let id = task.taskIdentifier

        let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
            let total = baseProgress + progress.fractionCompleted * weight
            continuation.yield(.progress(total))
        }

        observations[id] = observation

        let localURL = try await withCheckedThrowingContinuation { cont in
            continuations[id] = cont
            task.resume()
        }

        if let expected = expectedMD5 {
            do {
                let md5 = try localURL.md5String()
                if md5.lowercased() != expected.lowercased() {
                    try? FileManager.default.removeItem(at: localURL)
                    throw Error.checksumMismatch
                }
            } catch {
                try? FileManager.default.removeItem(at: localURL)
                throw error
            }
        }

        return localURL
    }
}

extension VoiceLoader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier

        do {
            let tempLocation = try FileManager.default.moveToTemporaryDirectory(fileURL: location)
            continuations[id]?.resume(returning: tempLocation)
        } catch {
            Log.error("Failed to move file to temporary location: \(error)")
            continuations[id]?.resume(throwing: error)
        }

        continuations[id] = nil
        observations[id]?.invalidate()
        observations[id] = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Swift.Error?
    ) {
        let id = task.taskIdentifier
        continuations[id]?.resume(throwing: error ?? URLError(.unknown))
        continuations[id] = nil
        observations[id]?.invalidate()
        observations[id] = nil
    }
}
