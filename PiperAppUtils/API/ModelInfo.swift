// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation

public struct ModelInfo: Decodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case dataset
        case piperVersion = "piper_version"
        case language
        case audio
        case speakersInternal = "speaker_id_map"
        case numberOfSpeakersInternal = "num_speakers"
    }
    
    public let dataset: String?
    public let piperVersion: String
    public let language: Language
    public let audio: Audio
    private let speakersInternal: [String: Int]?
    public var speakers: [String: Int] {
        speakersInternal ?? [:]
    }
    private let numberOfSpeakersInternal: Int?
    public var numberOfSpeakers: Int {
        numberOfSpeakersInternal ?? 1
    }
    
    public var name: String {
        return dataset ?? "Unknown"
    }
    
    public enum Error: Swift.Error {
        case nilFileURL
    }
    
    public static func create(from fileURL: URL?) throws -> ModelInfo {
        guard let fileURL else {
            throw Error.nilFileURL
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let jsonDecoder = JSONDecoder()
        return try jsonDecoder.decode(ModelInfo.self, from: data)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let loose = try decoder.container(keyedBy: FlexibleCodingKey.self)

        self.dataset = try container.decodeIfPresent(String.self, forKey: .dataset)
            ?? loose.string(for: "name")
            ?? loose.string(for: "model_name")
            ?? loose.string(for: "model_type")
            ?? loose.string(for: "comment")
            ?? loose.string(for: "description")

        self.piperVersion = try container.decodeIfPresent(String.self, forKey: .piperVersion)
            ?? loose.string(for: "version")
            ?? loose.string(for: "tts_version")
            ?? loose.string(for: "model_type")
            ?? "external"

        if let language = try container.decodeIfPresent(Language.self, forKey: .language) {
            self.language = language
        } else {
            let code = loose.string(for: "language_code")
                ?? loose.string(for: "language")
                ?? loose.string(for: "lang")
                ?? "en_US"
            let family = code.split(separator: "_").first.map(String.init) ?? code
            let region = code.split(separator: "_").dropFirst().first.map(String.init) ?? family.uppercased()
            self.language = Language(code: code, family: family, region: region)
        }

        if let audio = try container.decodeIfPresent(Audio.self, forKey: .audio) {
            self.audio = audio
        } else {
            let sampleRate = loose.double(for: "sample_rate") ?? loose.double(for: "sampleRate") ?? 24000.0
            self.audio = Audio(sampleRate: sampleRate, quality: loose.string(for: "quality") ?? "downloaded")
        }

        self.speakersInternal = try container.decodeIfPresent([String: Int].self, forKey: .speakersInternal)
            ?? loose.dictionary(for: "speakers")
            ?? loose.dictionary(for: "speaker_id_map")
            ?? loose.dictionary(for: "voices")

        self.numberOfSpeakersInternal = try container.decodeIfPresent(Int.self, forKey: .numberOfSpeakersInternal)
            ?? loose.int(for: "n_speakers")
            ?? loose.int(for: "num_speakers")
            ?? speakersInternal?.count
    }
    
    public static var installed: ModelInfo? {
        if FileManager.default.isInstalled {
            let modelInfoJson = FileManager.Constants.jsonModelURL
            return try? create(from: modelInfoJson)
        }
        return nil
    }
    
    public static var installedModels: [ModelInfo] {
        FileManager.ModelPaths.installedModels.compactMap { path in
            path.info
        }
    }
    
    public var installedPath: FileManager.ModelPaths? {
        return FileManager.ModelPaths.installedModels.first { paths in
            (paths.info) == self
        }
    }

    public static let separator = ">0<"
    public var voiceId: String {
        let components = [
            name,
            audio.quality,
            "\(audio.sampleRate)",
            "\(language.code)",
            "\(numberOfSpeakers)"
        ]
        return components.joined(separator: Self.separator)
    }
    
    public static func installedModelInfo(for voiceId: String) -> ModelInfo? {
        let components = voiceId.split(separator: Self.separator)
        guard components.count == 5 else {
            return nil
        }
        
        let name = String(components[0])
        let quality = String(components[1])
        let languageCode = String(components[3])
        
        let numberOfSpeakersString = String(components[4]).components(separatedBy: Constants.speakerIdSeparator).first
        return installedModels.first { model in
            return model.name == name &&
            model.language.code == languageCode &&
            numberOfSpeakersString == "\(model.numberOfSpeakers)" &&
            quality == model.audio.quality
        }
    }
}

extension ModelInfo: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(piperVersion)
        hasher.combine(language)
        hasher.combine(audio)
        hasher.combine(speakers)
        hasher.combine(numberOfSpeakers)
    }
}

extension ModelInfo: Equatable {
    static public func == (lhs: ModelInfo, rhs: ModelInfo) -> Bool {
        lhs.name == rhs.name
        && lhs.piperVersion == rhs.piperVersion
        && lhs.language == rhs.language
        && lhs.audio == rhs.audio
        && lhs.speakers == rhs.speakers
        && lhs.numberOfSpeakers == rhs.numberOfSpeakers
    }
}

private struct FlexibleCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == FlexibleCodingKey {
    func string(for key: String) -> String? {
        guard let codingKey = FlexibleCodingKey(stringValue: key) else {
            return nil
        }

        if let stringValue = try? decodeIfPresent(String.self, forKey: codingKey) {
            return stringValue
        }
        if let intValue = try? decodeIfPresent(Int.self, forKey: codingKey) {
            return "\(intValue)"
        }
        return nil
    }

    func int(for key: String) -> Int? {
        guard let codingKey = FlexibleCodingKey(stringValue: key) else {
            return nil
        }

        if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
            return value
        }
        if let stringValue = try? decodeIfPresent(String.self, forKey: codingKey) {
            return Int(stringValue)
        }
        return nil
    }

    func double(for key: String) -> Double? {
        guard let codingKey = FlexibleCodingKey(stringValue: key) else {
            return nil
        }

        if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
            return value
        }
        if let intValue = try? decodeIfPresent(Int.self, forKey: codingKey) {
            return Double(intValue)
        }
        if let stringValue = try? decodeIfPresent(String.self, forKey: codingKey) {
            return Double(stringValue)
        }
        return nil
    }

    func dictionary(for key: String) -> [String: Int]? {
        guard let codingKey = FlexibleCodingKey(stringValue: key) else {
            return nil
        }

        if let dictionary = try? decodeIfPresent([String: Int].self, forKey: codingKey) {
            return dictionary
        }
        if let names = try? decodeIfPresent([String].self, forKey: codingKey) {
            return Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, $0.offset) })
        }
        return nil
    }
}
