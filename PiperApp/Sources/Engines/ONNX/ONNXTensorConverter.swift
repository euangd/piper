// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation

enum ONNXTensorConverter {
    static func data<T>(from values: [T], as type: T.Type = T.self) -> Data {
        values.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
    }

    static func values<T>(from data: Data, as type: T.Type = T.self) -> [T] {
        guard !data.isEmpty else {
            return []
        }

        let elementCount = data.count / MemoryLayout<T>.stride
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return []
            }

            let typedPointer = baseAddress.assumingMemoryBound(to: T.self)
            let typedBuffer = UnsafeBufferPointer(start: typedPointer, count: elementCount)
            return Array(typedBuffer)
        }
    }
}
