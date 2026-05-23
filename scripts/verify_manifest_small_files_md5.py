"""
Verify small file MD5 digests from the bundled English manifest.

Usage:
    python scripts/verify_manifest_small_files_md5.py [--manifest PATH] [--max-size BYTES] [--limit N]

This script downloads small files (e.g. .onnx.json, MODEL_CARD) referenced in the manifest
and checks that the reported `md5_digest` matches the downloaded content.

It is intended as a quick CI/validation helper for the manifest and downloader behavior.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path
from typing import Dict, Any

DEFAULT_MANIFEST = Path(__file__).resolve().parents[1] / "PiperApp" / "Resources" / "manifests" / "huggingface_piper_en.json"


def md5_of_bytes(b: bytes) -> str:
    m = hashlib.md5()
    m.update(b)
    return m.hexdigest()


def download_bytes(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "piper-manifest-check/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    ap.add_argument("--max-size", type=int, default=100_000, help="Max file size in bytes to download and check (default 100k)")
    ap.add_argument("--limit", type=int, default=20, help="Max number of files to check")
    args = ap.parse_args(argv)

    manifest_path: Path = args.manifest
    if not manifest_path.exists():
        print(f"Manifest file not found at {manifest_path}")
        return 2

    data = json.loads(manifest_path.read_text(encoding="utf-8"))

    failures = 0
    checked = 0

    # Iterate voices -> files
    for voice_key, voice in data.items():
        files: Dict[str, Any] = voice.get("files", {})
        for file_path, meta in files.items():
            if checked >= args.limit:
                break
            url = meta.get("url")
            md5_expected = meta.get("md5_digest")
            size_bytes = meta.get("size_bytes") or 0
            if not url or not md5_expected:
                continue
            # Only check small files to avoid downloading large models
            if size_bytes > args.max_size:
                continue

            try:
                print(f"Checking {voice_key} -> {file_path} ({size_bytes} bytes) ... ", end="", flush=True)
                content = download_bytes(url)
                digest = md5_of_bytes(content)
                if digest.lower() == md5_expected.lower():
                    print("OK")
                else:
                    print(f"MISMATCH (expected {md5_expected} got {digest})")
                    failures += 1
                checked += 1
            except Exception as e:
                print(f"ERROR: {e}")
                failures += 1
                checked += 1

        if checked >= args.limit:
            break

    print(f"Checked {checked} files, failures: {failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
