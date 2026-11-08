"""Check packaged Mach-O dependencies and record their SHA-256 identities."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'app.ryu.ios.melonx', info['CFBundleIdentifier']
assert float(info['MinimumOSVersion']) >= 27
assert not (app / 'PlugIns').exists(), 'Unexpected embedded helper/app ID'
native = []
for file in sorted(app.rglob('*')):
    if not file.is_file(): continue
    magic = file.read_bytes()[:4]
    if magic not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'): continue
    result = subprocess.run(['xcrun', 'otool', '-L', str(file)], capture_output=True, text=True, check=True)
    dependencies = []
    for line in result.stdout.splitlines()[1:]:
        dep = line.strip().split(' (compatibility version')[0]
        if not dep or 'architecture ' in dep: continue
        dependencies.append(dep)
        if dep.startswith(('/System/', '/usr/lib/')): continue
        if dep.startswith('@rpath/'):
            tail = dep.removeprefix('@rpath/')
            candidates = [app / 'Frameworks' / tail, app / tail]
        elif dep.startswith('@loader_path/'):
            candidates = [file.parent / dep.removeprefix('@loader_path/')]
        elif dep.startswith('@executable_path/'):
            candidates = [app / dep.removeprefix('@executable_path/')]
        else:
            raise RuntimeError(f'Unreviewed absolute native dependency: {file}: {dep}')
        if not any(candidate.exists() for candidate in candidates):
            raise RuntimeError(f'Missing packaged dependency: {file.relative_to(app)}: {dep}')
    native.append(dict(path=str(file.relative_to(app)), sha256=hashlib.sha256(file.read_bytes()).hexdigest(), dependencies=dependencies))
assert len(native) >= 5, 'Native engine/frameworks missing'
(app / 'SourceNotices/native-manifest.json').write_text(json.dumps(native, indent=2) + '\n')
print(f'PASS iOS 27 IPA structure, bundle identity, {len(native)} native dependency closures; SHA-256 manifest recorded.')
