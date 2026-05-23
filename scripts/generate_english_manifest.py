#!/usr/bin/env python3
"""
Download the upstream voices.json from HuggingFace, filter to English-only voices,
and write a manifest with absolute download URLs and metadata.

Usage:
  python scripts/generate_english_manifest.py

Output:
  PiperApp/BuildScripts/Resources/voices_english_manifest.json
"""
import json
import os
import sys
from urllib.request import urlopen

DEFAULT_VOICES_URL = "https://huggingface.co/IhorShevchuk/piper1-voices-fp16-quantized/resolve/main/voices.json"
BASE_RESOLVE = "https://huggingface.co/IhorShevchuk/piper1-voices-fp16-quantized/resolve/main"
OUT_PATH = os.path.join("PiperApp", "BuildScripts", "Resources", "voices_english_manifest.json")


def fetch_json(url):
    with urlopen(url) as resp:
        data = resp.read()
        return json.loads(data)


def ensure_dir_for(path):
    d = os.path.dirname(path)
    if d and not os.path.exists(d):
        os.makedirs(d, exist_ok=True)


def build_manifest(voices_index):
    manifest = {}
    for key, entry in voices_index.items():
        lang = entry.get("language", {})
        family = (lang.get("family") or "").lower()
        code = (lang.get("code") or "").lower()
        if family != "en" and not code.startswith("en"):
            continue

        files = entry.get("files", {})
        files_out = {}
        for relpath, meta in files.items():
            files_out[relpath] = {
                "url": f"{BASE_RESOLVE}/{relpath}",
                "size_bytes": meta.get("size_bytes"),
                "md5_digest": meta.get("md5_digest")
            }

        out_entry = {
            "key": entry.get("key", key),
            "name": entry.get("name"),
            "language": entry.get("language"),
            "quality": entry.get("quality"),
            "num_speakers": entry.get("num_speakers"),
            "speaker_id_map": entry.get("speaker_id_map", {}),
            "files": files_out,
            "aliases": entry.get("aliases", [])
        }
        manifest[key] = out_entry

    return manifest


def main():
    print("Fetching voices.json from HuggingFace...")
    try:
        voices = fetch_json(DEFAULT_VOICES_URL)
    except Exception as e:
        print("Failed to fetch voices.json:", e, file=sys.stderr)
        sys.exit(1)

    print("Building English-only manifest...")
    manifest = build_manifest(voices)

    ensure_dir_for(OUT_PATH)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    print(f"Wrote English manifest to {OUT_PATH} with {len(manifest)} voices")


if __name__ == "__main__":
    main()
