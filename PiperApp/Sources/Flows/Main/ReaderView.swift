// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import SwiftUI
import PiperAppUtils
import UniformTypeIdentifiers

struct ReaderView: View {
    @StateObject var hostModel: ReaderHostModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isWebsiteImportShown: Bool = false
    @State private var isFileImporterShown: Bool = false
    @State private var websiteURLString: String = ""
    
    let initialImportType: ImportType?
    
    enum ImportType {
        case website
        case file
    }
    
    private var importableTextTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .pdf, .rtf]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return types
    }
    
    @ViewBuilder
    private func buttonImageView(systemName: String) -> some View {
        Image(systemName: systemName)
            .imageScale(.large)
            .foregroundColor(.accentColor)
    }
    
    var body: some View {
        Form {
            Section("Document Text") {
                TextEditor(text: $hostModel.viewModel.demoText)
                    .frame(minHeight: 150)
            }
            
            Section("Settings") {
                if hostModel.installedVoices.isEmpty {
                    Text("No voices installed. Install a voice model first.")
                        .foregroundColor(.red)
                } else {
                    Picker("Voice", selection: $hostModel.selectedVoice) {
                        ForEach(hostModel.installedVoices, id: \.id) { voice in
                            Text("\(voice.info?.name.capitalized ?? "") (\(voice.engine.displayName))")
                                .tag(Optional(voice))
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text(String(format: "%.1fx", hostModel.viewModel.speed))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $hostModel.viewModel.speed, in: 0.5...2.0, step: 0.1)
                }
            }
            
            Section("Playback") {
                HStack {
                    Button {
                        hostModel.play()
                    } label: {
                        CenteredContent {
                            if hostModel.viewModel.isPlaying && !hostModel.viewModel.isPaused {
                                buttonImageView(systemName: "pause")
                                Text("Pause")
                            } else {
                                buttonImageView(systemName: "play")
                                Text(hostModel.viewModel.isPaused ? "Resume" : "Play")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(hostModel.installedVoices.isEmpty)

                    if hostModel.viewModel.isPlaying || hostModel.viewModel.isPaused {
                        Button {
                            hostModel.stop()
                        } label: {
                            CenteredContent {
                                buttonImageView(systemName: "stop")
                                Text("Stop")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                
                if hostModel.viewModel.isPlaying || hostModel.viewModel.isPaused {
                    VStack(spacing: 4) {
                        ProgressView(value: hostModel.viewModel.playbackProgress)
                            .progressViewStyle(.linear)
                        
                        HStack {
                            Text(hostModel.viewModel.elapsedTime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(hostModel.viewModel.timeRemaining)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Section("Import Content") {
                Button {
                    isWebsiteImportShown = true
                } label: {
                    Label("Import Website", systemImage: "link")
                }
                .disabled(hostModel.viewModel.isImportingText)

                Button {
                    isFileImporterShown = true
                } label: {
                    Label("Import Text File", systemImage: "doc.text")
                }
                .disabled(hostModel.viewModel.isImportingText)

                if hostModel.viewModel.isImportingText {
                    ProgressView()
                }

                if let importError = hostModel.viewModel.importError {
                    Text(importError)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Document Reader")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if initialImportType == .website {
                isWebsiteImportShown = true
            } else if initialImportType == .file {
                isFileImporterShown = true
            }
        }
        .sheet(isPresented: $isWebsiteImportShown) {
            NavigationStack {
                Form {
                    TextField("Website URL", text: $websiteURLString)
#if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
#endif
                }
                .navigationTitle("Import Website")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isWebsiteImportShown = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            hostModel.importWebsite(websiteURLString)
                            isWebsiteImportShown = false
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $isFileImporterShown, allowedContentTypes: importableTextTypes) { result in
            switch result {
            case .success(let url):
                hostModel.importTextFile(url)
            case .failure(let error):
                hostModel.viewModel.importError = error.localizedDescription
            }
        }
    }
}
