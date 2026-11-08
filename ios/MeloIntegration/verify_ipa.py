"""Check native dependencies and hash nested code before sealing the main app."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'app.fow.explorer', info['CFBundleIdentifier']
assert float(info['MinimumOSVersion']) >= 27
helpers = list((app / 'PlugIns').iterdir())
assert len(helpers) == 1 and helpers[0].name == 'MeloNXRamDonor.appex', helpers
helper = helpers[0]
helper_info = plistlib.loads((helper / 'Info.plist').read_bytes())
assert helper_info['CFBundleIdentifier'] == 'app.fow.explorer.RamDonor', helper_info
assert float(helper_info['MinimumOSVersion']) >= 27
assert helper_info['NSExtension']['NSExtensionPrincipalClass'] == 'MLXRamDonorHandler'
assert helper_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.ar.viewer'
assert (helper / helper_info['CFBundleExecutable']).is_file()
subprocess.run(['codesign', '--verify', '--strict', str(helper)], check=True)
main_executable = app / info['CFBundleExecutable']
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
    entry = dict(path=str(file.relative_to(app)), dependencies=dependencies)
    if file != main_executable:
        entry['sha256'] = hashlib.sha256(file.read_bytes()).hexdigest()
    else:
        # Root signing seals this manifest and changes the executable signature.
        # Avoid a self-hash cycle; the final IPA's SHA-256 covers the root code.
        entry['hash_coverage'] = 'Final IPA SHA-256; root signed after manifest'
    native.append(entry)
assert len(native) >= 5, 'Native engine/frameworks missing'
(app / 'SourceNotices/native-manifest.json').write_text(json.dumps(native, indent=2) + '\n')
print(f'PASS iOS 27 app and stock RAM helper identities, {len(native)} native dependency closures; nested SHA-256 manifest recorded.')
