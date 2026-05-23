// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import Foundation
import PiperAppUtils

extension FileManager {
    enum InstallError: Swift.Error {
        case invalidSourceFiles
        case invalidDestinationURLs
        case cantParseModelInfo
    }
    
    func install(paths: ModelPaths?) throws {
        guard let paths else {
            throw InstallError.invalidSourceFiles
        }
        
        // Create an install folder and preserve original filenames (folder-centric install)
        guard let modelsFolder = FileManager.Constants.modelsFolderURL else {
            throw InstallError.invalidDestinationURLs
        }
        let installFolder = modelsFolder.appendingPathComponent(UUID().uuidString)
        let destinationModelURL = installFolder.appendingPathComponent(paths.model.lastPathComponent)
        let destinationJsonURL = installFolder.appendingPathComponent(paths.json.lastPathComponent)
        guard let destination = ModelPaths(model: destinationModelURL, json: destinationJsonURL, engine: paths.engine) else {
            throw InstallError.invalidDestinationURLs
        }
        
        do {
            if let info = paths.info,
               let installedPath = ModelPaths.installedModel(matching: info, engine: paths.engine) {
                try uninstall(paths: installedPath)
            }
        } catch {
            Log.debug("Error happened while uninstalling. Error: \(error)")
        }
        
        let fileManager = FileManager.default
        // Create folder and copy files preserving their original filenames.
        // Non-Piper engines are model bundles, so install every sibling file when
        // the selected model/config came from the same source folder.
        try fileManager.createModelPathsFolder(paths: destination)
        if paths.model.deletingLastPathComponent() == paths.json.deletingLastPathComponent(),
           let sourceFiles = fileManager.flatFiles(in: paths.model.deletingLastPathComponent()) {
            for sourceFile in sourceFiles where !sourceFile.hasDirectoryPath {
                let target = installFolder.appendingPathComponent(sourceFile.lastPathComponent)
                if !fileManager.fileExists(atPath: target.path) {
                    try fileManager.copyItem(at: sourceFile, to: target)
                }
            }
        } else {
            try fileManager.copyItem(at: paths.json, to: destination.json)
            try fileManager.copyItem(at: paths.model, to: destination.model)
        }
        var installedModels = FileManager.ModelPaths.installedModels
        installedModels.append(destination)
        FileManager.ModelPaths.installedModels = installedModels
    }
    
    func uninstall(paths: ModelPaths?) throws {
        
        guard let installed = paths else {
            throw InstallError.invalidDestinationURLs
        }
        
        var installedModels = FileManager.ModelPaths.installedModels
        installedModels.removeAll(where: { path in
            path == paths
        })
        FileManager.ModelPaths.installedModels = installedModels
        let fileManager = FileManager.default
        try fileManager.removeItem(at: installed.model)
        try fileManager.removeItem(at: installed.json)
        
        if let modelFolder = installed.modelFolder {
            try fileManager.removeItem(at: modelFolder)
        }
    }
    
    enum Error: Swift.Error {
        case nilTemporaryDirectory
    }
    
    static var tempFolderInDocumentDirectory: URL? {
        let temporaryDirectoryURL = URL(filePath: NSTemporaryDirectory())
        return temporaryDirectoryURL.appending(component: "temporary_folder")
    }
    
    func createTemporaryDirectoryIfNeeded() throws {
        guard let temporaryDirectoryURL = FileManager.tempFolderInDocumentDirectory else {
            throw Error.nilTemporaryDirectory
        }
        if !FileManager.default.fileExists(atPath: temporaryDirectoryURL.path) {
            try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    func cleanTemporaryDirectory() throws {
        guard let temporaryDirectoryURL = FileManager.tempFolderInDocumentDirectory else {
            throw Error.nilTemporaryDirectory
        }
        let fileManager = FileManager.default
        try fileManager.removeItem(at: temporaryDirectoryURL)
    }
    
    func moveToTemporaryDirectory(fileURL: URL) throws -> URL {
        guard let temporaryDirectoryURL = FileManager.tempFolderInDocumentDirectory else {
            throw Error.nilTemporaryDirectory
        }
        try createTemporaryDirectoryIfNeeded()
        let movedFileURL = temporaryDirectoryURL.appendingPathComponent(UUID().uuidString)
        try self.copyItem(at: fileURL, to: movedFileURL)
        return movedFileURL
    }

    func flatFiles(in folder: URL) -> [URL]? {
        guard let enumerator = enumerator(at: folder,
                                          includingPropertiesForKeys: [.isRegularFileKey],
                                          options: [.skipsHiddenFiles]) else {
            return nil
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return url
        }
    }
}

extension FileManager.ModelPaths {
    var modelTitle: String {
        guard let modelInfo = info else {
            return "Unknown"
        }
        
        return "\(modelInfo.name.capitalized) \(modelInfo.language.code.localizedLanguageFromCode)"
    }

    var engineTitle: String {
        engine.displayName
    }
}
