// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import CommonCrypto

extension Data {
    var md5String: String {
        // If you really need MD5 for backward compatibility, use CommonCrypto
        // Otherwise, consider migrating to SHA256
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        self.withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress, CC_LONG(self.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension URL {
    func md5String() throws -> String {
        let data = try Data(contentsOf: self)
        return data.md5String
    }
}
