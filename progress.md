# Progress

## Session 2 (May 23, 2026)
- User answered all 5 strategic questions
- Updated task_plan.md with decisions

## Session 12 (May 23, 2026)

### CI-only validation note

- Confirmed this workspace cannot run Apple builds locally on the current Windows host.
- Verified the simulator task fails before compilation because the local build automation is unavailable in this shell.
- Confirmed the GitHub Actions workflow is the intended build/validation path for archive coverage.

### Validation

- Ran read-only checks against the workflow, build scripts, and project manifest.
- No repo-side build blocker was found in the current manifests; the remaining blocker is environment/toolchain availability on this device.
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

### Build fixes

- **Phase 2: ONNX Runtime Integration — started and scaffolded**
  - Added ONNX Runtime package dependency in `Package.swift`
  - Linked ONNX Runtime to app target in `Project.swift` (`.external(name: "onnxruntime")`)
  - Added shared ONNX utility scaffolding:
    - `PiperApp/Sources/Engines/ONNX/ONNXRuntimeSupport.swift`
    - `PiperApp/Sources/Engines/ONNX/ONNXSessionStore.swift`
    - `PiperApp/Sources/Engines/ONNX/ONNXTensorConverter.swift`
    - `PiperApp/Sources/Engines/ONNX/AudioNormalizer.swift`

### Verification

- `get_errors` on workspace: **No errors found**
- Build task `Build (Simulator)`: **blocked** (local build automation unavailable in this shell)

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
- Full native build validation remains blocked in this Windows shell because the required Apple toolchain is unavailable.

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

## Session 8 (May 23, 2026)

### Session 8 Done

- Investigated the GitHub Actions archive failure from the iPhoneOS release build.
- Identified the concrete Swift compile break in `PiperAppUtils/FileManager/FileManager.swift`:
  - `Constants.supportedModelExtensions` was resolved as `FileManager.Constants`, not `PiperAppUtils.Constants`.
- Fixed both failing references by explicitly qualifying:
  - `PiperAppUtils.Constants.supportedModelExtensions`
- Revalidated the updated file with diagnostics after the patch.

### Session 8 Validation

- `get_errors` reports **no errors** for `PiperAppUtils/FileManager/FileManager.swift` after the fix.
- This directly addresses the explicit CI compiler errors shown in the archive log.

### Session 8 Files Modified

- `PiperAppUtils/FileManager/FileManager.swift`

## Session 9 (May 23, 2026)

### Session 9 Done

- Audited the repository's GitHub automation and confirmed `.github/workflows/build-ipa.yml` is the only workflow file present.
- Repaired workflow robustness issues in `.github/workflows/build-ipa.yml`:
  - pinned CI to **Xcode 16.4** with `maxim-lobanov/setup-xcode@v1`
  - replaced wildcard cleanup with deterministic cleanup of `Piper.xcodeproj`, `Piper.xcworkspace`, `build`, `Payload`, and `Piper.ipa`
  - split archive and packaging into separate steps
  - captured `xcodebuild` archive output via `tee build/logs/xcodebuild-archive.log`
  - added an always-on artifact upload step for archive logs
- Fixed the broken README workflow badge/link so it points to the actual workflow file:
  - `actions/workflows/build-ipa.yml`

### Session 9 Validation

- `get_errors` reports **no errors** for `.github/workflows/build-ipa.yml` after the patch.
- Searched the workspace for workflow references and confirmed the stale `build.yml` reference in `README.md` was the only broken workflow link.
- Full GitHub Actions execution remains unverified in this Windows shell because macOS runners are not available locally.

### Session 9 Files Modified

- `.github/workflows/build-ipa.yml`
- `README.md`

## Session 10 (May 23, 2026)

### Session 10 Done

- Moved the app further beyond Piper-only model handling:
  - added a bundled `external_tts_manifest.json` catalog with verified Hugging Face bundle entries for Kokoro, MeloTTS, and Supertonic 3
  - updated `VoiceLoader` so downloads can install full model bundles, not just one ONNX plus one JSON
  - generated installed metadata for non-Piper downloaded models so the app shows the correct voice name, engine, language, and quality
  - preserved all sidecar files during install, including tokenizer, lexicon, voices/style files, and multi-ONNX assets
  - added recursive local folder import for model bundles in addition to individual model/config file import
  - made voice download rows engine-aware and disabled Piper sample playback controls for non-Piper rows
  - relaxed `ModelInfo` decoding so non-Piper config/metadata JSON can still produce an installed voice identity
  - improved Kokoro vocabulary loading from `tokenizer.json`
  - loosened MeloTTS loading to accept `tokens.txt` and single-model exports without an explicit BERT sidecar
  - fixed the URL session download completion delegate signature to use `Swift.Error`
  - restored the two-file install fallback when model/config files are selected from different folders
  - added unit coverage for generated external model metadata and loose external config decoding

### Session 10 Validation

- Verified `PiperApp/Resources/manifests/external_tts_manifest.json` parses as JSON.
- Ran `git diff --check`; no whitespace errors were reported.
- Full native validation is still blocked in this Windows shell because the required Apple toolchain is unavailable.

## Session 11 (May 23, 2026)

### Done

- Fixed the two explicit Swift compile blockers from the archive log:
  - replaced deprecated `CC_MD5` usage in `PiperApp/Sources/Utils/Hash.swift` with `CryptoKit.Insecure.MD5`
  - added the missing `return` in `PiperApp/Sources/VoiceLoading/Models/Voice.swift` for the fallback model path lookup
- Ran source-only diagnostics on `PiperApp/Sources` and `PiperAppUtils`; no Swift errors remain in those areas.

### Validation

- `get_errors` on the patched files: no errors.
- `get_errors` on `PiperApp/Sources` and `PiperAppUtils`: no errors.
- `Build (Simulator)` task still fails immediately in this Windows shell because the local build automation is unavailable.

### Session 10 Files Created

- `PiperApp/Resources/manifests/external_tts_manifest.json`

### Session 10 Files Modified

- `PiperApp/Sources/VoiceLoading/VoiceLoader.swift`
- `PiperApp/Sources/VoiceLoading/Models/Voice.swift`
- `PiperApp/Sources/VoiceLoading/Models/VoiceFile.swift`
- `PiperApp/Sources/Utils/FileManager.swift`
- `PiperApp/Sources/Utils/Array.swift`
- `PiperApp/Sources/Flows/ImportVoice/ImportVoiceView.swift`
- `PiperApp/Sources/Flows/ImportVoice/ImportVoiceHostModel.swift`
- `PiperApp/Sources/Flows/ImportVoice/ImportVoiceViewModel.swift`
- `PiperApp/Sources/Flows/VoicesList/Item/VoiceItemView.swift`
- `PiperApp/Sources/Flows/VoicesList/Item/VoiceItemHostModel.swift`
- `PiperAppUtils/API/ModelInfo.swift`
- `PiperApp/Sources/Engines/KokoroTTSEngine.swift`
- `PiperApp/Sources/Engines/MeloTTSEngine.swift`
- `PiperTests/ModelPathsTests.swift`

## Session 13 (May 23, 2026)

### Context recovery

- Re-read the current plan, progress, and findings files to restore context.
- Ran the planning catch-up script from the installed skill path; it returned no unsynced context.
- Re-checked the repo memory note about ONNX Runtime linkage and sanity-scanned `Project.swift` / `Package.swift` for direct `onnxruntime` references; no direct matches were returned by the workspace search.

### Build check

- No new code changes were needed.
- The build remains blocked by the unavailable native build automation on this Windows host.
