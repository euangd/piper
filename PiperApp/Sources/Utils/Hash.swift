// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import CryptoKit

extension Data {
    var md5String: String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension URL {
    func md5String() throws -> String {
        let data = try Data(contentsOf: self)
        return data.md5String
    }
}
