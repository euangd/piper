// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
typealias ONNXRuntimeSessionType = ORTSession
#else
typealias ONNXRuntimeSessionType = AnyObject
#endif

enum ONNXRuntimeSupport {
    static var isAvailable: Bool {
        #if canImport(OnnxRuntimeBindings)
        true
        #else
        false
        #endif
    }
}
