// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import SwiftUI
import PiperAppUtils
import UniformTypeIdentifiers

struct VoiceView: View {
    
    @StateObject var hostModel: VoiceHostModel
    @Environment(\.dismiss) private var popView
    @State private var isWebsiteImportShown: Bool = false
    @State private var isFileImporterShown: Bool = false
    @State private var websiteURLString: String = ""

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
    
    @ViewBuilder
    func playSampleView() -> some View {
        Section {
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
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.bordered)

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
                
                ShareLink("export_file".localized, item: VoiceFileTransferable(text: hostModel.viewModel.demoText, syntehesizer: hostModel),
                          preview: SharePreview(hostModel.fileName + ".wav",
                                                icon: Image("waveform")
                                               ))
                .tint(.accentColor)
                .buttonStyle(.bordered)
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in
                return 0
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
            if let modelInfo = hostModel.viewModel.modelInfo {
                if !modelInfo.speakers.isEmpty {
                    Picker("speaker".localized, selection: $hostModel.viewModel.selectedSpeaker) {
                        ForEach(modelInfo.speakers.keys.sorted(), id: \.self) { speakerKey in
                            Text(speakerKey.capitalized)
                                .tag(modelInfo.speakers[speakerKey]!)
                        }
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
            
            TextField("sample_text".localized, text: $hostModel.viewModel.demoText, axis: .vertical)
                .lineLimit(1...10)
                .accessibilityLabel("sample_text: \(hostModel.viewModel.demoText)")
        }
    }

    @ViewBuilder
    func textImportView() -> some View {
        Section {
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
    
    @State var unstallConfirmationShown: Bool = false
    @ViewBuilder
    func uninstall() -> some View {
        Button {
            unstallConfirmationShown.toggle()
        } label: {
            CenteredContent {
                Text("uninstall_voice")
                    .foregroundStyle(.red)
            }
        }
        .alert("uninstall_voice", isPresented: $unstallConfirmationShown) {
            Button("uninstall_button", role: .destructive) {
                hostModel.uninstall()
                popView()
            }
            Button("cancel", role: .cancel) {
                unstallConfirmationShown.toggle()
            }
        }
    }
    
    var body: some View {
        List {
            if let modelInfo = hostModel.viewModel.modelInfo {
                ModelInfoView(info: modelInfo, detailed: true)
            }
            
            textImportView()

            playSampleView()
            
            Section {
                uninstall()
            }
        }
        .navigationTitle(hostModel.viewModel.paths.info?.name.capitalized ?? "voice")
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
                        Button("cancel") {
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
