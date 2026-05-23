// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import XCTest
@testable import PiperAppUtils

final class ModelPathsTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testPrimaryModelURLPrefersCanonicalModelWhenPresent() throws {
        let paths = try makePaths(canonicalModelName: "canonical.onnx")
        let canonicalURL = try writeFile(named: "canonical.onnx")

        XCTAssertEqual(paths.primaryModelURL?.standardizedFileURL,
                       canonicalURL.standardizedFileURL)
    }

    func testPrimaryModelURLFallsBackToDiscoveredSupportedExtension() throws {
        let paths = try makePaths(canonicalModelName: "missing.onnx")
        let discoveredURL = try writeFile(named: "voice.ggml")

        XCTAssertEqual(paths.primaryModelURL?.standardizedFileURL,
                       discoveredURL.standardizedFileURL)
    }

    func testFindFilePrefersNamedMatchWithinPreferredExtensions() throws {
        let paths = try makePaths(canonicalModelName: "missing.onnx")
        _ = try writeFile(named: "model.json")
        let expectedURL = try writeFile(named: "model.onnx")

        XCTAssertEqual(
            paths.findFile(matchingNameCandidates: ["model"], preferredExtensions: ["onnx"] )?.standardizedFileURL,
            expectedURL.standardizedFileURL
        )
    }

    func testFindFileDoesNotReturnWrongExtensionWhenPreferredExtensionMissing() throws {
        let paths = try makePaths(canonicalModelName: "missing.onnx")
        _ = try writeFile(named: "model.json")

        XCTAssertNil(paths.findFile(matchingNameCandidates: ["model"], preferredExtensions: ["onnx"]))
    }

    func testExistUsesDiscoveredPrimaryModelWhenCanonicalModelIsMissing() throws {
        let paths = try makePaths(canonicalModelName: "missing.onnx")
        _ = try writeFile(named: "voice.tflite")

        XCTAssertTrue(paths.exist)
    }

    private func makePaths(canonicalModelName: String,
                           jsonName: String = "voice.json") throws -> FileManager.ModelPaths {
        let modelURL = temporaryDirectory.appendingPathComponent(canonicalModelName)
        let jsonURL = temporaryDirectory.appendingPathComponent(jsonName)
        try Data("{}".utf8).write(to: jsonURL)
        return try XCTUnwrap(FileManager.ModelPaths(model: modelURL, json: jsonURL))
    }

    @discardableResult
    private func writeFile(named name: String, contents: String = "fixture") throws -> URL {
        let fileURL = temporaryDirectory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }
}
