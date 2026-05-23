// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

struct VoiceFile: Decodable {
    let url: String?
    let size_bytes: Int
    let md5_digest: String?
}

extension VoiceFile: Equatable {
    static func == (lhs: VoiceFile, rhs: VoiceFile) -> Bool {
        lhs.url == rhs.url && lhs.size_bytes == rhs.size_bytes && lhs.md5_digest == rhs.md5_digest
    }
}

extension VoiceFile: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(size_bytes)
        hasher.combine(md5_digest)
    }
}
