from pathlib import Path
p=Path('PiperApp/Resources/manifests/huggingface_piper_en.json')
s=p.read_text(encoding='utf-8')
if '... (file continues)' in s:
    print('Found placeholder, removing...')
    s2=s.replace('... (file continues)','')
    p.write_text(s2, encoding='utf-8')
    print('Fixed file')
else:
    print('No placeholder found')
