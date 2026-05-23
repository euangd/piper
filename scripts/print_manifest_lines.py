from pathlib import Path
p=Path('PiperApp/Resources/manifests/huggingface_piper_en.json')
lines=p.read_text(encoding='utf-8').splitlines()
for i in range(228,242):
    print(i+1, repr(lines[i]))
