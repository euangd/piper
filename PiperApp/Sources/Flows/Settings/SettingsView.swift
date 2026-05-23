// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import SwiftUI
import PiperAppUtils

struct SettingsView: View {
    @AppStorage("defaultEngine") private var defaultEngine: String = "piper"
    @AppStorage("defaultSpeed") private var defaultSpeed: Double = 1.0
    
    @State private var storageSize: String = "Calculating..."
    @State private var installedCount: Int = 0
    @State private var isClearingTemp: Bool = false
    @State private var clearStatusMessage: String?
    
    var body: some View {
        Form {
            Section("Playback Defaults") {
                Picker("Default Engine", selection: $defaultEngine) {
                    Text("Piper").tag("piper")
                    Text("MeloTTS").tag("meloTTS")
                    Text("Kokoro").tag("kokoro")
                    Text("Supertonic 3").tag("supertonic3")
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Default Speed")
                        Spacer()
                        Text(String(format: "%.1fx", defaultSpeed))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $defaultSpeed, in: 0.5...2.0, step: 0.1)
                }
            }
            
            Section("Storage Management") {
                HStack {
                    Text("Installed Voices")
                    Spacer()
                    Text("\(installedCount)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Voice Storage Size")
                    Spacer()
                    Text(storageSize)
                        .foregroundColor(.secondary)
                }
                
                Button(role: .destructive) {
                    clearTemporaryFiles()
                } label: {
                    HStack {
                        if isClearingTemp {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("Clear Temporary Files")
                    }
                }
                .disabled(isClearingTemp)
                
                if let msg = clearStatusMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            updateStorageStats()
        }
    }
    
    private func updateStorageStats() {
        installedCount = FileManager.ModelPaths.installedModels.count
        storageSize = getInstalledVoicesSize()
    }
    
    private func clearTemporaryFiles() {
        isClearingTemp = true
        clearStatusMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.cleanTemporaryDirectory()
                DispatchQueue.main.async {
                    self.isClearingTemp = false
                    self.clearStatusMessage = "Temporary files cleared successfully."
                    self.updateStorageStats()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isClearingTemp = false
                    self.clearStatusMessage = "Failed to clear temporary files: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func getInstalledVoicesSize() -> String {
        guard let modelsFolder = FileManager.Constants.modelsFolderURL else {
            return "0 KB"
        }
        do {
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(at: modelsFolder, includingPropertiesForKeys: [.fileSizeKey], options: [])
            var totalSize: Int64 = 0
            for file in files {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: file.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        let subPaths = try fileManager.subpathsOfDirectory(atPath: file.path)
                        for subPath in subPaths {
                            let subFilePath = file.appendingPathComponent(subPath)
                            let attrs = try fileManager.attributesOfItem(atPath: subFilePath.path)
                            if let size = attrs[.size] as? Int64 {
                                totalSize += size
                            }
                        }
                    } else {
                        let attrs = try fileManager.attributesOfItem(atPath: file.path)
                        if let size = attrs[.size] as? Int64 {
                            totalSize += size
                        }
                    }
                }
            }
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useAll]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: totalSize)
        } catch {
            return "0 KB"
        }
    }
}
