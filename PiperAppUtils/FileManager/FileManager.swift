// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation

extension FileManager {
    public struct ModelPaths {
        public let model: URL
        public let json: URL
        public let info: ModelInfo?
        public let engine: TTSEngineType
        public init?(model: URL?, json: URL?, engine: TTSEngineType = .piper) {
            guard let model, let json else {
                return nil
            }
            self.model = model
            self.json = json
            self.info = try? ModelInfo.create(from: json)
            self.engine = engine
        }
        
        public var exist: Bool {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: json.path) else {
                return false
            }

            return fileManager.fileExists(atPath: model.path) || primaryModelURL != nil
        }
        
        public var modelFolder: URL? {
            if self == ModelPaths.engine {
                return nil
            }
            
            let modelParent = model.deletingLastPathComponent()
            let jsonParent = json.deletingLastPathComponent()
            if modelParent == jsonParent {
                return modelParent
            }
            return nil
        }
        
        public static var engine: ModelPaths? {
            return ModelPaths(model: FileManager.Constants.modelURL,
                              json: FileManager.Constants.jsonModelURL)
        }
        
        public static func installNew(engine: TTSEngineType = .piper) -> ModelPaths? {
            guard let modelsFolder = FileManager.Constants.modelsFolderURL else {
                return nil
            }
            let installNewFolder = modelsFolder.appendingPathComponent(UUID().uuidString)
            return ModelPaths(model: installNewFolder.appendingPathComponent(PiperAppUtils.Constants.modelFileNameWithExtension),
                              json: installNewFolder.appendingPathComponent(PiperAppUtils.Constants.modelJSONFileNameWithExtension),
                              engine: engine)
        }

        public var isInstalled: Bool {
            if self == ModelPaths.engine && exist {
                return true
            }
            
            return ModelPaths.installed.contains(self)
        }

        /// Returns a best-effort primary model file URL for this `ModelPaths`.
        /// Preference order:
        /// 1. If `model` exists, return it.
        /// 2. Search by canonical/generic model names constrained to supported model extensions.
        /// 3. Search any file matching supported model extensions in extension priority order.
        /// 4. `nil` if nothing suitable is discoverable.
        public var primaryModelURL: URL? {
            let fm = FileManager.default
            if fm.fileExists(atPath: model.path) {
                return model
            }

            let canonicalModelName = model.deletingPathExtension().lastPathComponent
            let candidateNames = [canonicalModelName, "model", "tts_model"]
                .filter { !$0.isEmpty }

            if let found = findFile(matchingNameCandidates: candidateNames,
                                    preferredExtensions: PiperAppUtils.Constants.supportedModelExtensions) {
                return found
            }

            return findFile(withExtensions: PiperAppUtils.Constants.supportedModelExtensions)
        }

        /// Find a file in the same model folder matching any of the provided name candidates or extensions.
        /// Search order:
        /// 1. If `model` exists and matches a candidate while satisfying preferred extensions, return it.
        /// 2. Exact filename match among preferred extensions.
        /// 3. Filename without extension equals candidate among preferred extensions.
        /// 4. Filename contains candidate as substring among preferred extensions.
        /// 5. Any file matching preferred extensions (in order).
        /// 6. If no preferred extensions are provided, repeat exact / basename / substring match against all files.
        /// 7. `nil` if nothing found.
        public func findFile(matchingNameCandidates names: [String], preferredExtensions exts: [String] = []) -> URL? {
            let fm = FileManager.default

            let lowerNames = Array(Set(names.map { $0.lowercased() }.filter { !$0.isEmpty }))
            let lowerExts = Array(Set(exts.map { $0.lowercased() }.filter { !$0.isEmpty }))

            func matchesPreferredExtension(_ url: URL) -> Bool {
                lowerExts.isEmpty || lowerExts.contains(url.pathExtension.lowercased())
            }

            func exactMatch(in files: [URL]) -> URL? {
                for candidate in lowerNames {
                    if let found = files.first(where: { $0.lastPathComponent.lowercased() == candidate }) {
                        return found
                    }
                }
                return nil
            }

            func basenameMatch(in files: [URL]) -> URL? {
                for candidate in lowerNames {
                    if let found = files.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == candidate }) {
                        return found
                    }
                }
                return nil
            }

            func containsMatch(in files: [URL]) -> URL? {
                for candidate in lowerNames {
                    if let found = files.first(where: { $0.lastPathComponent.lowercased().contains(candidate) }) {
                        return found
                    }
                }
                return nil
            }

            // 1. Check model itself
            if fm.fileExists(atPath: model.path) {
                let base = model.lastPathComponent.lowercased()
                let baseWithoutExtension = model.deletingPathExtension().lastPathComponent.lowercased()
                if matchesPreferredExtension(model) &&
                    (lowerNames.contains(base) || lowerNames.contains(baseWithoutExtension)) {
                    return model
                }
            }

            guard let folder = modelFolder,
                  let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    .sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) else {
                return nil
            }

            let preferredFiles = lowerExts.isEmpty ? files : files.filter(matchesPreferredExtension)

            // 2-4. Preferred-extension exact / basename / contains matching.
            if let found = exactMatch(in: preferredFiles)
                ?? basenameMatch(in: preferredFiles)
                ?? containsMatch(in: preferredFiles) {
                return found
            }

            // 5. Preferred extensions in priority order.
            if !lowerExts.isEmpty {
                for ext in lowerExts {
                    if let found = preferredFiles.first(where: { $0.pathExtension.lowercased() == ext }) {
                        return found
                    }
                }
            }

            // 6. Without preferred extensions, allow general name-based discovery.
            if lowerExts.isEmpty,
               let found = exactMatch(in: files)
                ?? basenameMatch(in: files)
                ?? containsMatch(in: files) {
                return found
            }

            return nil
        }

        /// Find any file in model folder that matches one of the provided extensions (in order).
        public func findFile(withExtensions exts: [String]) -> URL? {
            let fm = FileManager.default
            guard let folder = modelFolder,
                                    let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                                        .sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) else {
                return nil
            }
            for ext in exts.map({ $0.lowercased() }) {
                if let found = files.first(where: { $0.pathExtension.lowercased() == ext }) {
                    return found
                }
            }
            return nil
        }

        public static func installedModel(matching info: ModelInfo, engine: TTSEngineType) -> ModelPaths? {
            installedModels.first { paths in
                paths.engine == engine && paths.info == info
            }
        }
        
        @FileBacked<[ModelPaths]>(default: [], urlProvider: {
            Constants.modelsJsonURL
        }) static var installed
        
        public static var installedModels: [ModelPaths] {
            get {
                var result = Set<ModelPaths>()
                if let legacy = ModelPaths.engine,
                    legacy.exist {
                    result.insert(legacy)
                }
                result.formUnion(installed)
                return Array(result)
            }
            set {
                self.installed = newValue
            }
        }
    }
    
    enum Error: Swift.Error {
        case nilModelFolderURL
    }
    
    public var isInstalled: Bool {
        guard let paths = ModelPaths.engine else {
            return false
        }
        return paths.exist
    }
    
    public func createModelPathsFolder(paths: ModelPaths) throws {
        guard let folder = paths.modelFolder else {
            throw Error.nilModelFolderURL
        }
        try createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
    }
}

extension FileManager.ModelPaths: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model.standardizedFileURL == rhs.model.standardizedFileURL &&
        lhs.json.standardizedFileURL == rhs.json.standardizedFileURL &&
        lhs.info == rhs.info &&
        lhs.engine == rhs.engine
    }
}

extension FileManager.ModelPaths: Codable {
    enum CodingKeys: String, CodingKey {
        case model
        case json
        case engine
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try values.decode(URL.self, forKey: .model)
        self.json = try values.decode(URL.self, forKey: .json)
        self.engine = try values.decodeIfPresent(TTSEngineType.self, forKey: .engine) ?? .piper
        self.info = try? ModelInfo.create(from: self.json)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(model, forKey: .model)
        try values.encode(json, forKey: .json)
        try values.encode(engine, forKey: .engine)
    }
}

extension FileManager.ModelPaths: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(model.standardizedFileURL)
        hasher.combine(json.standardizedFileURL)
        hasher.combine(info)
        hasher.combine(engine)
    }
}
