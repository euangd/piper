// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

class Voice: Decodable {
    let key: String
    let name: String
    let quality: String
    let language: PiperAppUtils.Language
    let files: [String: VoiceFile]
    let engine: TTSEngineType
    let summary: String?
    private var voiceSize: Int {
        return files.values.reduce(into: 0) { $0 += $1.size_bytes }
    }
    var voiceSizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(voiceSize), countStyle: .binary)
    }
    var modelPath: String? {
        if let explicit = files.first(where: { $0.value.role == "model" })?.key {
            return explicit
        }
        return Array(files.keys).model
    }
    var jsonPath: String? {
        if let explicit = files.first(where: { $0.value.role == "config" || $0.value.role == "metadata" })?.key {
            return explicit
        }
        return Array(files.keys).json
    }

    // If the manifest provides explicit absolute URLs for files, expose them here.
    var modelFileURL: URL? {
        guard let key = modelPath, let file = files[key], let urlString = file.url else {
            return nil
        }
        return URL(string: urlString)
    }

    var jsonFileURL: URL? {
        guard let key = jsonPath, let file = files[key], let urlString = file.url else {
            return nil
        }
        return URL(string: urlString)
    }

    enum CodingKeys: String, CodingKey {
        case key
        case name
        case quality
        case language
        case files
        case engine
        case summary
    }

    required init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try values.decode(String.self, forKey: .key)
        self.name = try values.decode(String.self, forKey: .name)
        self.quality = try values.decode(String.self, forKey: .quality)
        self.language = try values.decode(PiperAppUtils.Language.self, forKey: .language)
        self.files = try values.decode([String: VoiceFile].self, forKey: .files)
        self.engine = try values.decodeIfPresent(TTSEngineType.self, forKey: .engine) ?? .piper
        self.summary = try values.decodeIfPresent(String.self, forKey: .summary)
    }
}

extension Voice: Equatable {
    static func == (lhs: Voice, rhs: Voice) -> Bool {
        lhs.key == rhs.key &&
        lhs.name == rhs.name &&
        lhs.quality == rhs.quality &&
        lhs.language == rhs.language &&
        lhs.files == rhs.files &&
        lhs.engine == rhs.engine
    }
}

extension Voice: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(name)
        hasher.combine(quality)
        hasher.combine(language)
        hasher.combine(files)
        hasher.combine(engine)
    }
}
