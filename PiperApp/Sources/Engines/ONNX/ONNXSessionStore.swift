// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation

actor ONNXSessionStore {
    typealias SessionFactory = @Sendable (_ modelPath: String) throws -> ONNXRuntimeSessionType

    private var sessionsByModelPath: [String: ONNXRuntimeSessionType] = [:]

    func session(for modelPath: String, factory: SessionFactory) throws -> ONNXRuntimeSessionType {
        if let cached = sessionsByModelPath[modelPath] {
            return cached
        }

        let session = try factory(modelPath)
        sessionsByModelPath[modelPath] = session
        return session
    }

    func removeSession(for modelPath: String) {
        sessionsByModelPath[modelPath] = nil
    }

    func removeAllSessions() {
        sessionsByModelPath.removeAll()
    }
}
