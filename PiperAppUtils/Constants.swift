// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import UniformTypeIdentifiers

public enum Constants {
    public static let speakerIdSeparator = "<+>"
    public static let modelFileName = "model"
    public static let modelsFolderName = "models"
    public static let modelExtension = "onnx"
    /// Supported model file extensions (lowercased, without dot). Add new formats here as supported.
    public static let supportedModelExtensions: [String] = ["onnx", "ggml", "tflite", "pt", "bin"]
    public static let jsonModelExtension = "json"
    public static var modelFileNameWithExtension: String {
        return "\(modelFileName).\(modelExtension)"
    }
    public static var modelJSONFileNameWithExtension: String {
        return "\(modelFileNameWithExtension).\(jsonModelExtension)"
    }
    
    public static var modelsJSONFileName: String {
        return "\(modelsFolderName).\(jsonModelExtension)"
    }
    
    public static let jsonUTI: UTType = .json
    public static let modelUTI: UTType = .init(filenameExtension: modelExtension) ?? .item
}
