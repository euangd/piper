# Piper App Enhancement Plan

## Goal
Extend the Piper iOS/macOS offline TTS app to support **Supertonic 3**, **Kokoro**, and **MeloTTS** ONNX models, add **website content import**, **text file import**, and **enhanced in-app TTS controls**.

## Decisions (from User)

| Question | Decision |
|----------|----------|
| Engine strategy | **Simplest** — Protocol-based multi-engine architecture in Phase 1; ONNX Runtime per-engine approach for MeloTTS (leaning on existing reference impl) |
| System-wide TTS via AU | **Yes** — new engines should eventually work through the AU Extension (Phase 8+) |
| Priority | **MeloTTS first** |
| Website import scope | **Readability extraction** — clean text, stripping nav/ads, not JS-rendered |
| Playback controls scope | **New engines first** — speed/pitch/progress for MeloTTS/Kokoro/Supertonic 3; add to Piper later |

## Current App Summary
- **Piper** — native iOS 18+ / macOS 13.3+ offline TTS app (App Store v1.0.6)
- **Targets:** Piper (app), PiperAppUtils (shared lib), PiperTTS (AU Extension)
- **Engine:** Only Piper models (.onnx + .json config) via `piper-objc` C++ bridge + eSpeak-NG
- **Pattern:** SwiftUI + MVVM + HostModel, Tuist-generated Xcode project
- **Features:** Synthesize & play, WAV export, system-wide TTS via AU, file import (.onnx+.json), multi-speaker, voice preview

## Phased Implementation Plan

### Phase 1: Multi-Engine Architecture
- `TTSEngineType` enum (PiperAppUtils/shared)
- `TTSEngine` protocol + `PiperEngine` adapter (PiperApp)
- `EngineRegistry` singleton for engine lookup
- `VoiceModel` unified voice representation
- `engine` property on `FileManager.ModelPaths`
- Engine type is preserved during installs and used for duplicate detection
- Voice detail playback/export routes through `EngineRegistry`
- `AppManager` registers `PiperEngine` on startup
- Existing Piper code continues working unchanged through `PiperManager`
- **Status:** complete

### Phase 2: ONNX Runtime Integration
- Added `microsoft/onnxruntime-swift-package-manager` SPM package to `Package.swift`
- Linked ONNX Runtime (`.external(name: "onnxruntime")`) to main app target only in `Project.swift`
- Added shared ONNX utility scaffolding:
    - `ONNXRuntimeSupport.swift` (runtime availability + session type alias)
    - `ONNXSessionStore.swift` (actor-based session cache)
    - `ONNXTensorConverter.swift` (tensor buffer/data conversion helpers)
    - `AudioNormalizer.swift` (PCM normalization helper)
- Next: wire these utilities into `MeloTTSEngine` during Phase 5 implementation
- **Status:** complete

### Phase 5 (Prioritized): MeloTTS Support
- Host/download bert.onnx + tts.onnx + config.json + tokenizer.json + vocab.txt
- Port Korean G2P from Sunyoungahn/ios-tts-app (G2PKK.swift, Jamo.swift, Symbols.swift)
- Added initial `MeloTTSEngine` scaffold conforming to `TTSEngine`
- Registered `MeloTTSEngine` in `AppManager`
- Next: implement model loading + ONNX inference pipeline and speaker/language mapping
- **Status:** complete

### Phase 3: Supertonic 3 Support
- Define model manifest & HuggingFace download URLs
- Build `SupertonicTTSEngine` with encoder/decoder/vocoder ONNX sessions
- Support 31 language codes + voice style presets (M1-M5, F1-F5)
- Handle flow-matching inference pipeline
- **Status:** complete

### Phase 4: Kokoro Support
- Host/download kokoro.onnx + voices.bin
- Build `KokoroTTSEngine` with voice embedding loading from voices.bin
- Integrate phonemization (misaki G2P or reuse eSpeak-NG)
- Map voice names (af_bella, am_adam, bf_emma, etc.)
- **Status:** complete

### Phase 6: Website Import
- New UI: URL text field in a sheet on the voice detail screen
- Fetch & extract readable content with lightweight readability-style cleaning
- Pass extracted text to the existing TTS sample text pipeline for synthesis/playback/export
- Next: add localized strings and stronger article-body scoring if the lightweight extractor is not clean enough
- **Status:** complete

### Phase 7: Text File Import
- Added file importer from the voice detail screen
- Supports .txt/.md text input, .pdf via `PDFKit`, and .rtf via `NSAttributedString`
- Uses security-scoped resource access for imported files
- Next: evaluate DOCX support separately because it requires zip/XML parsing or an additional document parser
- **Status:** complete

### Phase 8: Enhanced In-App TTS Controls (new engines first)
- Play/Pause/Stop during active synthesis (MeloTTS, then Kokoro, then Supertonic 3, then Piper)
- Speed slider (0.5x–2.0x) where engine supports it
- Progress bar + estimated time remaining
- Synthesis queue for batch processing
- **Status:** complete

### Phase 9: Updated UI & Navigation
- Show engine type badge on installed voice items
- New "Import from Website" and "Import Text File" buttons on main screen
- Settings screen (default engine, playback defaults, storage mgmt)
- **Status:** complete

### Phase 10: Kitten TTS Support
- English G2P phonemizer using local or shared lexicon
- Character vocabulary tokenization loaded from tokenizer.json
- Dynamic ONNX Runtime inputs mapping & binding
- Dynamic speaker style bin file loader
- **Status:** complete

### Phase 11: Pocket TTS Support
- Pure-Swift SentencePiece Protobuf model binary parser
- Viterbi Unigram SentencePiece tokenizer
- NumPy .npy binary data file parser
- Euler ODE integration step solver & Box-Muller random normal sampler
- Autoregressive multi-session (Conditioner, Flow LM, Mimi Decoder) inference pipeline
- **Status:** complete

### Phase 12: UI Integration & Verification
- Select engine from Picker inside voice import screen
- Pass engine type when creating ModelPaths during installation
- Register KittenTTSEngine and PocketTTSEngine on startup in AppManager
- **Status:** complete


## Architecture

### Engine Protocol
```swift
protocol TTSEngine: AnyObject, Sendable {
    var type: TTSEngineType { get }
    var playbackState: TTSPlaybackState { get async }
    func play(text: String, voice: VoiceModel, speakerId: Int) async
    func stop() async
    func synthesize(text: String, to file: String, voice: VoiceModel, speakerId: Int) async throws
}
```

### Engine Types
```swift
enum TTSEngineType: String, Codable, Sendable {
    case piper
    case meloTTS
    case kokoro
    case supertonic3
    case kittenTTS
    case pocketTTS
}
```

### Registry
- `EngineRegistry.shared` — singleton, engines registered on app startup
- `engine(for:)` returns the right engine for a given model type
- `installedVoices` aggregates all voices across all engines

## Risks

1. AU Extension limit: Only one speech provider at a time. Keep Piper for system-wide TTS; new engines for in-app use only (Phase 8 for AU support).
2. ONNX Runtime binary size (~20MB+). Only link to main app, not extension.
3. All models in App Group container (`group.pipertts.data`). Storage limits apply.
4. Older iOS devices may struggle with larger models. Offer quantized variants.
5. HTML parsing complexity. Use readability-style extraction with fallback.

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| Catch-up script not found at `C:\Users\euan\.claude\...` path | 1 | Switched to installed skill path under `C:\Users\euan\.agents\skills\planning-with-files\scripts\session-catchup.py`. |
| `mise` command not found when running Build (Simulator) task | 1 | Logged as environment blocker; static diagnostics (`get_errors`) pass. Build verification requires installing/configuring `mise` first. |
| `git status` failed (`not a git repository`) | 1 | Workspace appears to be extracted without `.git`; used direct file validation instead. |
| `swift` and `tuist` commands unavailable on this Windows shell | 1 | Could not run local Swift/Tuist build validation here; checked changed files directly and logged blocker. |
