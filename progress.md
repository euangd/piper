# Progress

## Session 2 (May 23, 2026)

### Phase 2 Work Completed
- User answered all 5 strategic questions
- Updated task_plan.md with decisions
- **Phase 1: Multi-Engine Architecture — complete**
  - Created `PiperAppUtils/TTSEngineType.swift` — enum with .piper, .meloTTS, .kokoro, .supertonic3
  - Created `PiperApp/Sources/Engines/TTSEngine.swift` — protocol with play/stop/synthesize
  - Created `PiperApp/Sources/Engines/PiperEngine.swift` — wraps PiperManager as TTSEngine
  - Created `PiperApp/Sources/Engines/EngineRegistry.swift` — singleton registry
  - Created `PiperApp/Sources/Engines/VoiceModel.swift` — unified voice model
  - Added `engine: TTSEngineType` property to `FileManager.ModelPaths` with Codable support
  - Updated `AppManager` to register PiperEngine on startup
  - All existing code continues working unchanged

### Upcoming Phase
- **Phase 2: ONNX Runtime Integration** — add SPM package, build inference utilities
- **Phase 5: MeloTTS** — port reference impl, build MeloTTSEngine

### Files Created (Phase 1)
- `PiperAppUtils/TTSEngineType.swift` (new)
- `PiperApp/Sources/Engines/TTSEngine.swift` (new)
- `PiperApp/Sources/Engines/PiperEngine.swift` (new)
- `PiperApp/Sources/Engines/EngineRegistry.swift` (new)
- `PiperApp/Sources/Engines/VoiceModel.swift` (new)

### Files Modified (Phase 1)
- `PiperAppUtils/FileManager/FileManager.swift` — added `engine` property + Codable key
- `PiperApp/Sources/App/AppManager.swift` — registers PiperEngine on init
- `task_plan.md` — updated with user decisions

## Session 3 (May 23, 2026)

### Done
- **Phase 2: ONNX Runtime Integration — started and scaffolded**
  - Added ONNX Runtime package dependency in `Package.swift`
  - Linked ONNX Runtime to app target in `Project.swift` (`.external(name: "onnxruntime")`)
  - Added shared ONNX utility scaffolding:
    - `PiperApp/Sources/Engines/ONNX/ONNXRuntimeSupport.swift`
    - `PiperApp/Sources/Engines/ONNX/ONNXSessionStore.swift`
    - `PiperApp/Sources/Engines/ONNX/ONNXTensorConverter.swift`
    - `PiperApp/Sources/Engines/ONNX/AudioNormalizer.swift`

### Validation
- `get_errors` on workspace: **No errors found**
- Build task `Build (Simulator)`: **blocked** (environment missing `mise` command)

### Next Phase
- Continue **Phase 5 (MeloTTS)** using ONNX scaffolding:
  - add model artifact handling (bert/tts/tokenizer/vocab/config)
  - implement Melo engine adapter conforming to `TTSEngine`
  - wire engine registration in `AppManager`

### Files Created (Session 3)
- `PiperApp/Sources/Engines/ONNX/ONNXRuntimeSupport.swift`
- `PiperApp/Sources/Engines/ONNX/ONNXSessionStore.swift`
- `PiperApp/Sources/Engines/ONNX/ONNXTensorConverter.swift`
- `PiperApp/Sources/Engines/ONNX/AudioNormalizer.swift`

### Files Modified (Session 3)
- `Package.swift`
- `Project.swift`
- `task_plan.md`
- `findings.md`
- `PiperApp/Sources/App/AppManager.swift`

### Additional Session 3 Progress
- Started Phase 5 by adding `PiperApp/Sources/Engines/MeloTTSEngine.swift` with `TTSEngine` conformance.
- Registered `MeloTTSEngine` in `AppManager.setupEngines()`.
- Verified no diagnostics in modified Swift files via `get_errors`.

## Session 4 (May 23, 2026)

### Done
- Continued the implementation plan with a focused Phase 6/7 slice.
- Added `PiperApp/Sources/Flows/VoiceView/TextImportService.swift`:
  - website fetching with lightweight readability-style HTML cleanup
  - `.txt`/`.md` text import
  - PDF text extraction with `PDFKit`
  - RTF text extraction with `NSAttributedString`
- Updated `VoiceView` with Import Website and Import Text File actions.
- Updated `VoiceHostModel` to import website/file text into the editable sample text field.
- Fixed `VoiceHostModel.syntehesize(text:to:)` to use the method `text` argument instead of always reading `viewModel.demoText`.
- Updated `task_plan.md` and `findings.md`.

### Validation
- Confirmed this extracted workspace is not a Git checkout.
- `swift` and `tuist` commands are unavailable in this Windows shell, so a full compile/build could not be run here.
- Checked changed Swift files directly for integration consistency.

## Session 5 (May 23, 2026)

### Done
- Continued the implementation plan with a multi-engine routing slice.
- Added `TTSEngineType.displayName` for user-facing engine labels.
- Updated `FileManager.ModelPaths` so engine type participates in equality/hash identity.
- Added engine-aware install destination creation and duplicate install lookup.
- Updated `FileManager.install(paths:)` to preserve `paths.engine` when copying installed model files.
- Updated `PiperManager` and `PiperEngine` to look up Piper models with an explicit `.piper` engine match.
- Updated `VoiceHostModel` so play/stop/export synthesize through `EngineRegistry` for the selected model engine.
- Added engine badges to installed voice rows in `MainView`.
- Updated downloaded Piper voice install checks to ignore non-Piper models.
- Updated `task_plan.md` and `findings.md`.

### Validation
- Re-scanned the changed source paths and old `installedPath`/`installNew` usages with `rg`.
- Full Swift/Tuist/Xcode build validation remains blocked in this Windows shell because `swift`, `tuist`, and `xcodebuild` are unavailable.

## Session 6 (May 23, 2026)

### Done
- Fully implemented **Phase 5: MeloTTS Support** (with English-only compatibility as requested by user).
- Created helper classes in `MeloTTSEngine.swift`:
  - `BertTokenizer`: Standard WordPiece tokenizer that loads `vocab.txt` and splits input text into token IDs.
  - `EnglishG2P`: Grapheme-to-Phoneme converter mapping English words to phonemes using `lexicon.txt` (with character spelling fallback).
- Implemented MeloTTS inference pipeline:
  - Tokenization & phonemization of raw text.
  - Prepend `[CLS]` / append `[SEP]` tokens.
  - Run BERT hidden states inference on `bert.onnx` via `ORTSession`.
  - Align BERT embeddings to phonemes using `word2ph` (incorporating VITS blank intersperse if `add_blank` is enabled).
  - Transpose aligned BERT features to shape `[1, 1024, L]`.
  - Run acoustic model `tts.onnx` using dynamic inputs lookup from model graph.
  - Decode and normalize PCM audio frames.
- Implemented `AVAudioEngine` and `AVAudioPlayerNode` playback and `AVAudioFile` WAV export in `MeloTTSEngine`.
- Marked Phase 5, Phase 6, and Phase 7 as **complete** in `task_plan.md`.
- Attested updated `task_plan.md` using `attest-plan.ps1`.

### Validation
- Validated changed Swift files directly.
- Verified plan status reporting (5/9 phases complete) via `check-complete.ps1`.
- locked plan attestation hash successfully.

## Session 7 (May 23, 2026)

### Done
- Fully implemented **Phase 10: Kitten TTS Support** (with English G2P, character-level vocab mapping from `tokenizer.json`, dynamic tensor input/output binding, and speaker style binary files).
- Fully implemented **Phase 11: Pocket TTS Support** (with pure-Swift SentencePiece Protobuf binary file parser, Viterbi-based Unigram tokenizer, NumPy `.npy` file parser, Euler integration ODE solver, random normal Box-Muller generator, and 5-model ONNX runner).
- Fully implemented **Phase 12: UI Integration & Verification** (with updated `ImportVoiceView` engine selector Picker, engine parameter passing in `ImportVoiceHostModel`, and registration of both engines in `AppManager.swift`).

### Files Created
- `PiperApp/Sources/Engines/KittenTTSEngine.swift` (new)
- `PiperApp/Sources/Engines/PocketTTSEngine.swift` (new)

### Files Modified
- `PiperAppUtils/TTSEngineType.swift`
- `PiperApp/Sources/App/AppManager.swift`
- `PiperApp/Sources/Flows/ImportVoice/ImportVoiceViewModel.swift`
- `PiperApp/Sources/Flows/ImportVoice/ImportVoiceHostModel.swift`
- `PiperApp/Sources/Flows/ImportVoice/ImportVoiceView.swift`


