<p align="center">
  <a href="https://apps.apple.com/us/app/piper-neural-tts/id6759636010">
    <img src="PiperApp/Resources/piper_apple_app_logo.png" width="130"><br>
    <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" width="180">
  </a>
</p>

<h3 align="center">
  Piper is now available on the App Store! 🎉<br>
  Experience high-quality <b>offline neural text-to-speech</b> directly on your device.<br><br>
  Want to try the latest features early?<br>
  Join the <a href="https://testflight.apple.com/join/Adkg5F5H">TestFlight Beta</a> 🚀
</h3>

<p align="center">
  <a href="https://testflight.apple.com/join/Adkg5F5H">
    <img src="https://camo.githubusercontent.com/f8394f7cf70cc272e627e53e2d46241bc3fc83f145ee9e95a09a248efa2e72e8/68747470733a2f2f616e6f746865726c656e732e6170702f74657374666c696768742d62616467652e706e67" width="180">
  </a>
</p>

[![Build](https://github.com/IhorShevchuk/piper-app/actions/workflows/build-ipa.yml/badge.svg?branch=main)](https://github.com/IhorShevchuk/piper-app/actions/workflows/build-ipa.yml)

# 🌐 Help Translate Piper

We want to make **Piper** accessible to everyone, regardless of the language they speak! If you're fluent in another language, you can help us localize the app. No coding knowledge is required—all translations are managed through **Crowdin**.

## How to contribute:

1. Visit our [Crowdin Project Page](https://crowdin.com/project/piper-app).
2. Create a free account or sign in.
3. Select the language you'd like to help with.
4. Start translating or vote on existing suggestions!

If your language isn't listed yet, please [open an issue](https://github.com/IhorShevchuk/piper-app/issues) or request it directly on the Crowdin project page.


# 📥 Cloning & Building Piper

## System Requirements

* iOS 17.0+
* macOS 14.0+
* An Apple build environment for native app development

---

## Getting the Sources

```bash
git clone https://github.com/IhorShevchuk/piper-app.git
cd piper-app
```

---

## Generate the Workspace

Piper uses **Tuist** with Swift Package Manager for dependencies. First resolve SPM dependencies, then generate the workspace using the project’s automation scripts.

> **Note:** Re-run the dependency resolution step whenever `Package.swift` or dependencies change.

## English Voice Manifest

The app prefers a bundled English-only manifest at:

- `PiperApp/Resources/manifests/huggingface_piper_en.json`

`VoiceLoader` checks the app bundle first, then falls back to the upstream `voices.json` index if the bundled file is unavailable.

To regenerate the bundled English manifest:

```bash
python scripts/generate_english_manifest.py
```

To spot-check bundled file integrity against manifest MD5 values:

```bash
python scripts/verify_manifest_small_files_md5.py --manifest PiperApp/Resources/manifests/huggingface_piper_en.json --limit 8
```

## Tests

`Project.swift` defines a `PiperTests` unit-test target with coverage for `FileManager.ModelPaths` model discovery and fallback behavior.

After generating the workspace, run the `PiperTests` target from the Apple build environment's test runner or scheme picker.

---

# 📱 Running the App

## Simulator

1. Open the generated workspace in your Apple build environment
2. Select an iOS Simulator
3. Build & Run `Piper`

---

## Physical Device

1. Open the generated workspace in your Apple build environment
2. Select your device
3. Configure code signing for:
   * `Piper`
   * `PiperTTS`
