// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

struct VoiceFile: Decodable {
    let size_bytes: Int
}

extension VoiceFile: Equatable {
    static func == (lhs: VoiceFile, rhs: VoiceFile) -> Bool {
        lhs.size_bytes == rhs.size_bytes
    }
}

extension VoiceFile: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(size_bytes)
    }
}
