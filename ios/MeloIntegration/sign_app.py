"""Embed sideloader entitlement requests without an Apple signing identity.

AltStore must still provision and re-sign both bundles for the actual device.
Ad-hoc signatures preserve the requested capabilities; they do not grant them.
"""
import argparse
from pathlib import Path
import plistlib
import subprocess


def sign(path, entitlements=None):
    command = ['codesign', '--force', '--sign', '-', '--timestamp=none',
               '--generate-entitlement-der']
    if entitlements is not None:
        command += ['--entitlements', str(entitlements)]
    subprocess.run(command + [str(path)], check=True)


def entitlements(path):
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(path)],
                            check=True, capture_output=True)
    return plistlib.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('source_root', type=Path)
    parser.add_argument('--seal', action='store_true')
    args = parser.parse_args()
    app = args.app.resolve()
    source = args.source_root.resolve() / 'src/MeloNX'
    donor = app / 'PlugIns/MeloNXRamDonor.appex'
    assert donor.is_dir(), 'Stock MeloNX RAM helper was not embedded'
    requested = plistlib.loads((source / 'MeloNX/MeloNX.entitlements').read_bytes())
    assert requested['com.apple.developer.kernel.increased-memory-limit'] is True
    # Development re-signing needs debugger access for the user's StikDebug setup.
    requested['get-task-allow'] = True
    request_file = args.source_root / 'sideload.entitlements'
    request_file.write_bytes(plistlib.dumps(requested))

    if not args.seal:
        # Sign inside-out. Avoid --deep signing: only explicitly bundled code is
        # signed here, and the root is sealed after the native manifest is made.
        nested = list(app.rglob('*.framework')) + list(app.rglob('*.dylib'))
        for path in sorted(nested, key=lambda p: len(p.parts), reverse=True):
            sign(path)
        sign(donor, source / 'MeloNXRamDonor/MeloNXRamDonor.entitlements')
        print('PASS stock RAM donor and nested native code ad-hoc signatures')
        return

    assert (app / 'SourceNotices/native-manifest.json').is_file()
    sign(app, request_file)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    actual = entitlements(app)
    assert actual == requested, (actual, requested)
    # No elevated memory/debugger capability is added to the stock helper.
    helper_expected = plistlib.loads((source / 'MeloNXRamDonor/MeloNXRamDonor.entitlements').read_bytes())
    assert entitlements(donor) == helper_expected
    (args.source_root / 'packaged-entitlements.plist').write_bytes(plistlib.dumps(actual))
    print('PASS embedded increased-memory-limit/get-task-allow requests; sealed app and RAM helper signatures')


if __name__ == '__main__':
    main()
