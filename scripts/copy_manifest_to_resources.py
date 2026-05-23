from pathlib import Path
src=Path('PiperApp/BuildScripts/Resources/voices_english_manifest.json')
dst=Path('PiperApp/Resources/manifests/huggingface_piper_en.json')
if not src.exists():
    print('Source manifest missing:', src)
else:
    dst.write_bytes(src.read_bytes())
    print('Copied', src, '->', dst)
