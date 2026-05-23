from pathlib import Path
p=Path('PiperApp/Resources/manifests/huggingface_piper_en.json')
s=p.read_text(encoding='utf-8')
idx=8339
start=max(0,idx-60)
end=min(len(s), idx+60)
print('length', len(s))
print(s[start:end])
print('repr')
print(repr(s[start:end]))
