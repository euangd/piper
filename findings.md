# Findings

## App Architecture (Piper)

**Build:** Tuist 4.158.1, Xcode 16+, Swift 5.9
**Dependencies:** espeak-ng-spm, piper-objc (both by IhorShevchuk)
**Pattern:** SwiftUI + MVVM + HostModel
**Platforms:** iOS 18.0+, macOS 13.3+

### TTS Pipeline
Text -> AVSpeechSynthesisProviderRequest -> PiperTTSAudioUnit -> piper-objc (C++) -> eSpeak-NG phonemization -> PCM audio -> render/save

### Current Model Format (Piper only)
- .onnx + .json pair stored in App Group container (`group.pipertts.data`)
- JSON schema: dataset, piper_version, language, audio (sampleRate/quality), speakers, num_speakers
- Models downloaded from `huggingface.co/IhorShevchuk/piper1-voices-fp16-quantized`
- Installed models tracked via `@FileBacked[ModelPaths]` property wrapper (persisted to JSON in App Group)

### Key Source Files

| File | Purpose |
|------|---------|
| `PiperManager.swift` | Core synthesis: play, save-to-WAV, install/uninstall |
| `PiperAudioUnit.swift` | AVAudioUnit lifecycle, health checks, speech request dispatch |
| `PiperTTSAudioUnit.swift` | AU Extension core: Piper C++ engine integration, render block |
| `ModelInfo.swift` | .json config decoder, voiceId generation |
| `VoiceLoader.swift` | HuggingFace download manager with progress callbacks |
| `FileManager.swift` | ModelPaths struct, install/uninstall paths, `@FileBacked` tracking |
| `MainView.swift` | Root NavigationStack: installed voices list, download/import buttons |
| `VoiceView.swift` | Voice detail: speaker picker, text input, play/stop, export WAV |

## Model Research

### Supertonic 3
- **Developer:** Supertone Inc. Released April 29, 2026
- **Params:** ~99M (ONNX assets ~350MB full precision)
- **Languages:** 31 languages
- **Architecture:** Flow-matching text-to-latent + speech autoencoder
- **Features:** `<laugh>`, `<breath>`, `<sigh>` expressive tags, voice style presets (M1-M5, F1-F5)
- **HuggingFace:** Supertone/supertonic-3
- **sherpa-onnx variant:** csukuangfj2/sherpa-onnx-supertonic-3-tts-int8
- **RTF:** ~0.2 on CPU (competitive with GPU baselines)
- **License:** OpenRAIL-M (models), MIT (code)

### Kokoro
- **Developer:** hexgrad (Kokoro-82M), ONNX port by onnx-community & thewh1teagle
- **Params:** 82M
- **Variants:** fp32 310MB / fp16 163MB / int8 88MB
- **Voices:** 26+ (American/British English, male/female)
- **Model files:** kokoro-v1.0.onnx + voices-v1.0.bin (voice embeddings)
- **Requires:** G2P/phonemization (misaki recommended from v1.0)
- **Supported by:** sherpa-onnx
- **Python wrapper:** github.com/thewh1teagle/kokoro-onnx

### MeloTTS
- **Developer:** myshell-ai/MeloTTS
- **Languages:** CN, EN, KR, JP, ES, FR, etc.
- **Architecture:** VITS-based: bert.onnx + tts.onnx + config.json + tokenizer.json + vocab.txt
- **iOS reference:** github.com/Sunyoungahn/ios-tts-app — has Korean G2P engine (G2PKK.swift, Jamo.swift, Symbols.swift), MeloTTSInfer.mm (ObjC++ ONNX wrapper)
- **ONNX conversion:** github.com/season-studio/MeloTTS-ONNX
- **Supported by:** sherpa-onnx (as VITS-Melo model family)

### sherpa-onnx (k2-fsa)
- Mature inference engine supporting ASR + TTS + speaker recognition
- Already supports Piper, Supertonic 3, Kokoro, MeloTTS, and more
- Has iOS integration (used by BreezeApp from MediaTek Research)
- C/C++ library, Apache 2.0 license
- **This is the recommended unified approach** — one library supports all target models

### Sunyoungahn/ios-tts-app Structure
- MeloTTS iOS implementation with ONNX Runtime
- `MeloTTSInfer.mm` (Objective-C++) C++ wrapper for ONNX model
- `SimpleTTSEngine.swift` Swift interface
- Custom Korean G2P engine (G2PKK.swift) with liaison rules, consonant assimilation
- Audio visualization: WaveformView + SpectrogramView

## Session 3 Findings (Phase 2)

- ONNX Runtime SPM package is `https://github.com/microsoft/onnxruntime-swift-package-manager`.
- Current package release line includes 1.24.2; project updated to `from: "1.24.2"`.
- Tuist app target can link ONNX runtime as `.external(name: "onnxruntime")`.
- Kept ONNX dependency app-only (not linked in `PiperTTS` extension) to reduce extension footprint and complexity.
- Added shared ONNX utility scaffolding under `PiperApp/Sources/Engines/ONNX/` for:
  - runtime availability checks
  - actor-based session cache keyed by model path
  - tensor Data/[T] conversion helpers
  - audio peak normalization helper

## Session 4 Findings (Text Import)

- The app target already has `com.apple.security.network.client`, so website import can be implemented in the main app without adding new entitlements.
- `Project.swift` includes `PiperApp/Sources/**`, so new source files under `PiperApp/Sources/Flows/VoiceView/` are picked up automatically by Tuist.
- Voice detail is the lowest-risk integration point for imported text because `VoiceView` already owns the editable sample text used by play and export.
- Existing `VoiceHostModel.syntehesize(text:to:)` ignored its `text` argument and sent `viewModel.demoText` to Piper. Fixed while wiring import so export uses the explicit transfer text.

## Session 5 Findings (Engine Routing)

- `VoiceHostModel` still called `PiperManager` directly, which meant new engines registered in `EngineRegistry` could not be used from the voice detail screen.
- `FileManager.install(paths:)` created destination paths with the default `.piper` engine, so future non-Piper installs would lose their engine type unless installation preserved `paths.engine`.
- Duplicate install detection also needed to include engine type; matching only `ModelInfo` could remove a Piper voice when installing a future non-Piper model with similar metadata.
- The installed voices list used `info?.voiceId` as the SwiftUI identity, which is not unique across engines. The model URL is a safer row identity for installed model paths.

## Session 8 Findings (CI Archive Failure)

- The GitHub Actions archive failure was caused by a namespace collision inside `PiperAppUtils/FileManager/FileManager.swift`.
- Inside `extension FileManager`, unqualified `Constants.supportedModelExtensions` resolves to `FileManager.Constants`, which does **not** define `supportedModelExtensions`.
- The intended symbol lives in `PiperAppUtils.Constants.supportedModelExtensions`.
- The archive log's hard failure lines:
  - `type 'FileManager.Constants' has no member 'supportedModelExtensions'`
  - exactly matched the two references in `ModelPaths.primaryModelURL`.
- Explicitly qualifying those references with `PiperAppUtils.Constants` should unblock the `PiperAppUtils` Swift compile step in CI.

## Session 9 Findings (Workflow Audit)

- `.github/workflows/build-ipa.yml` is the repository's only GitHub Actions workflow file.
- The workflow previously relied on the runner's default Xcode selection; pinning `maxim-lobanov/setup-xcode@v1` to **16.4** matches the archive log environment (`/Applications/Xcode_16.4.app`) and reduces runner drift.
- Splitting archive and IPA packaging into separate steps makes failures easier to localize in Actions logs.
- Piping `xcodebuild` through `tee` while keeping `set -euo pipefail` preserves the real archive exit status and produces a reusable `build/logs/xcodebuild-archive.log` artifact.
- `README.md` referenced `actions/workflows/build.yml`, but no such workflow exists in this repo; the actual workflow path is `actions/workflows/build-ipa.yml`.

## Session 10 Findings (Model Bundle Import/Download)

- The previous downloader still had a Piper-shaped assumption: one model file plus one JSON config. Kokoro, MeloTTS, and Supertonic 3 need full folders with tokenizer, lexicon, voice/style, and multi-ONNX sidecars.
- `FileManager.install(paths:)` copied only `paths.model` and `paths.json`, so non-Piper downloads/imports lost the files required for inference. Installing every sibling file from the selected source folder preserves those bundles.
- Downloaded non-Piper configs often are not Piper `ModelInfo` JSON. Generating a small installed metadata JSON gives the app stable display names and duplicate detection while keeping the original engine files in the same installed folder.
- Kokoro's current public ONNX bundle stores its vocabulary in `tokenizer.json` under `model.vocab`, while `config.json` only identifies the model type. The engine now checks both.
- The verified catalog entries currently point at:
  - `onnx-community/Kokoro-82M-v1.0-ONNX`
  - `MiaoMint/MeloTTS-ONNX`
  - `Supertone/supertonic-3`
- Runtime synthesis still needs real Apple toolchain/device validation. The downloader/importer path can be validated statically here, but ONNX model input compatibility needs a macOS/iOS run.
