"""Reproducible MeloNX + Ryubing integration. Never runs supplied build scripts."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEST = ROOT / 'ios/build/melonx'
GIT = ROOT / 'ios/build/melonx-merge.git'
MELO = '13700519f3abc4e6d7ed8a065b118b2cc59bcd67'
RYU = 'a61a42681119bf15fe8f3297677ae48bda83e70f'
BASE = '69c22a744e14b2dcc5e2e1ee6f85d305a56a9403'

def git(*args, check=True):
    return subprocess.run(['git', '--git-dir=' + str(GIT), *args], check=check, capture_output=True)

def edit(path, old, new):
    target = DEST / path
    text = target.read_text(encoding='utf-8-sig')
    if old not in text:
        raise RuntimeError('Patch context changed: ' + path + ': ' + old[:80])
    target.write_text(text.replace(old, new), encoding='utf-8', newline='\n')

def prepare(offline=False):
    if not GIT.exists():
        subprocess.run(['git', 'init', '--bare', str(GIT)], check=True)
    if not offline:
        git('fetch', '--depth=256', 'https://starforgejo.dev/projects/MeloNX.git', MELO)
        git('fetch', '--depth=256', 'https://git.ryujinx.app/projects/Ryubing.git', RYU)
    actual = git('merge-base', MELO, RYU).stdout.decode().strip()
    if actual != BASE:
        raise RuntimeError('Unexpected merge ancestry: ' + actual)
    merge = git('merge-tree', '--write-tree', '--messages', MELO, RYU, check=False)
    if merge.returncode not in (0, 1):
        raise RuntimeError(merge.stderr.decode())
    tree = merge.stdout.decode().splitlines()[0]
    if DEST.exists():
        assert DEST.resolve().parent == (ROOT / 'ios/build').resolve()
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(git('archive', tree).stdout)) as archive:
        archive.extractall(DEST, filter='data')
    # Confirm the native input identities match the supplied source inventory.
    inventory = json.loads((ROOT / 'ios/SecurityReview/native-dependencies.json').read_text(encoding='utf-8-sig'))
    assert inventory['commit'] == MELO
    for binary in inventory['nativeBinaries']:
        actual_hash = hashlib.sha256((DEST / binary['path']).read_bytes()).hexdigest()
        if actual_hash != binary['sha256']:
            raise RuntimeError('Native input differs from reviewed inventory: ' + binary['path'])
    resolutions = json.loads((HERE / 'resolutions.json').read_text(encoding='utf-8-sig'))
    pattern = re.compile(r'^<<<<<<< [^\n]+\n(.*?)^=======\n(.*?)^>>>>>>> [^\n]+\n', re.M | re.S)
    for file in resolutions:
        path = DEST / file['path']
        source = path.read_text(encoding='utf-8-sig')
        blocks = list(pattern.finditer(source))
        if len(blocks) != len(file['blocks']):
            raise RuntimeError('Conflict count changed: ' + file['path'])
        for match, block in reversed(list(zip(blocks, file['blocks']))):
            assert match[1] == block['ours'] and match[2] == block['theirs'], file['path']
            source = source[:match.start()] + block['resolution'] + source[match.end():]
        path.write_text(source, encoding='utf-8', newline='\n')
    # Reviewable text overlays, including security fixes and API adaptations.
    overlay = HERE / 'overlay'
    if overlay.exists():
        shutil.copytree(overlay, DEST, dirs_exist_ok=True)
    swift = 'src/MeloNX/MeloNX/'
    path = DEST / (swift + 'Common/AppEnvironment.swift')
    source = path.read_text(encoding='utf-8-sig')
    start = source.index('            case "gameInfo":')
    end = source.index('            default:', start)
    source = source[:start] + '            case "gameInfo":\n                // Do not disclose the library to arbitrary callback applications.\n                return\n' + source[end:]
    path.write_text(source, encoding='utf-8', newline='\n')
    path = DEST / (swift + 'Common/JIT/EnableJIT.swift')
    source = path.read_text(encoding='utf-8-sig')
    start = source.index('        var urlScheme: String = "stikjit://enable-jit"')
    end = source.index('\n    }\n}', start)
    source = source[:start] + '''        var components = URLComponents()
        components.scheme = "stikdebug"
        components.host = "enable-jit"
        components.queryItems = [
            URLQueryItem(name: "bundle-id", value: bundle),
            URLQueryItem(name: "pid", value: String(getpid())),
            URLQueryItem(name: "script-name", value: "universal.js")
        ]
        if let launchURL = components.url { openURL(launchURL) }''' + source[end:]
    source = source[:source.index('// Universal Script')]
    path.write_text(source, encoding='utf-8', newline='\n')
    path = DEST / (swift + 'Core/RyujinxController.swift')
    source = path.read_text(encoding='utf-8-sig')
    # These optional entitlements are not a reliable capability test with free
    # development signing. The native allocator reports actual reservation errors.
    start = source.index('        if !hasIncreasedMemoryLimitEntitlement {')
    end = source.index('        if !isJITEnabled {', start)
    source = source[:start] + source[end:]
    source = source.replace('        Thread.detachNewThread {', '        let gameThread = Thread {', 1)
    needle = '\n        }\n    }\n    \n    \n    func redirectStdIOToFile()'
    assert needle in source
    source = source.replace(needle, '\n        }\n        gameThread.name = "Ryu emulation"\n        gameThread.stackSize = 8 * 1024 * 1024\n        gameThread.start()\n    }\n    \n    \n    func redirectStdIOToFile()', 1)
    path.write_text(source, encoding='utf-8', newline='\n')
    edit(swift + 'Core/Memory/RamDonor.swift', '"donateGuestMemory", default: true', '"donateGuestMemory", default: false')
    for path in (DEST / swift).rglob('*.swift'):
        source = path.read_text(encoding='utf-8-sig')
        updated = source.replace('donateGuestMemory(true)', 'donateGuestMemory(false)').replace('donateGpuBuffers(true)', 'donateGpuBuffers(false)')
        updated = updated.replace('jitProvider(JITProvider.disabled)', 'jitProvider(JITProvider.stikdebug)')
        if updated != source: path.write_text(updated, encoding='utf-8', newline='\n')
    edit('src/Ryujinx.Cpu/LightningJit/TranslatorStubs.cs',
         'public TranslatorStubs(IAddressTable<ulong> functionTable, DualMappedNoWxCache dualMappedNoWxCache)',
         'public TranslatorStubs(JitCache jitCache, IAddressTable<ulong> functionTable, DualMappedNoWxCache dualMappedNoWxCache)')
    edit('src/Ryujinx.Cpu/LightningJit/TranslatorStubs.cs',
         '            _functionTable = functionTable;\n            _dualMappedNoWxCache',
         '            _jitCache = jitCache;\n            _functionTable = functionTable;\n            _dualMappedNoWxCache')
    edit('src/Ryujinx.Cpu/LightningJit/TranslatorStubs.cs',
         'if (_noWxCache == null || _dualMappedNoWxCache == null)',
         'if (_noWxCache == null && _dualMappedNoWxCache == null)')
    for name in ('INotificationServices', 'INotificationSystemEventAccessor'):
        edit('src/Ryujinx.HLE/HOS/Services/Notification/' + name + '.cs',
             'class ' + name + ' :', 'partial class ' + name + ' :')
    # Upstream replaced this service with INotificationServices (same notif:s
    # name); keeping both creates duplicate registration in the AOT generator.
    (DEST / 'src/Ryujinx.HLE/HOS/Services/Notification/INotificationServicesForSystem.cs').unlink()
    edit('src/Ryujinx.Input.Native/NativeGamepad.cs',
         'public void Rumble(float lowFrequency, float highFrequency, uint durationMs)',
         'public bool Rumble(float lowFrequency, float highFrequency, uint durationMs)')
    edit('src/Ryujinx.Input.Native/NativeGamepad.cs',
         '        public void Rumble(GamepadVibrationValue',
         '''        public bool HDRumble(Ryujinx.HLE.HOS.Services.Hid.VibrationValue left, Ryujinx.HLE.HOS.Services.Hid.VibrationValue right)
        {
            Rumble(new GamepadVibrationValue(left.AmplitudeLow, left.FrequencyLow, left.AmplitudeHigh, left.FrequencyHigh),
                   new GamepadVibrationValue(right.AmplitudeLow, right.FrequencyLow, right.AmplitudeHigh, right.FrequencyHigh), uint.MaxValue);
            return true;
        }

        public void Rumble(GamepadVibrationValue''')
    edit('src/Ryujinx.Input.Native/NativeGamepad.cs',
         'RightFrequencyHigh = 320f,\n            });',
         'RightFrequencyHigh = 320f,\n            });\n            return true;')
    edit('src/Ryujinx.Library/Native/NativeMouse.cs',
         'public void Rumble(float lowFrequency, float highFrequency, uint durationMs)',
         'public bool HDRumble(Ryujinx.HLE.HOS.Services.Hid.VibrationValue left, Ryujinx.HLE.HOS.Services.Hid.VibrationValue right) => false;\n\n        public bool Rumble(float lowFrequency, float highFrequency, uint durationMs)')
    edit('src/Ryujinx.Library/Library.cs',
         'using Key = Ryujinx.Common.Configuration.Hid.Key;',
         'using Key = Ryujinx.Common.Configuration.Hid.PhysicalKey;')
    edit('src/Ryujinx.Library/Window/WindowBase.cs',
         'Thread renderLoopThread = new(Render)', 'Thread renderLoopThread = new(Render, 8 * 1024 * 1024)')
    edit('nuget.config', 'https://starforgejo.dev/api/packages/Ryulynx/nuget/index.json',
         'https://git.ryujinx.app/api/packages/projects/nuget/index.json')
    # Old MoltenVK dependency was renamed upstream. Native copy is selected explicitly.
    edit('src/Ryujinx.Library/Ryujinx.Library.csproj',
         'Ryujinx.Graphics.Vulkan.Dependencies.MoltenVK', 'Ryujinx.Graphics.Vulkan.MoltenVK')
    # Source generators execute on the build host; never inherit iOS/AOT globals.
    for project in (DEST / 'src').glob('*Generator*/*.csproj'):
        source = project.read_text(encoding='utf-8-sig')
        source = source.replace('<Project Sdk="Microsoft.NET.Sdk">',
            '<Project Sdk="Microsoft.NET.Sdk" TreatAsLocalProperty="PublishAot;PublishAotUsingRuntimePack;SelfContained;RuntimeIdentifier;IsAotCompatible;SupportedOSPlatformVersion">')
        source = source.replace('</Project>', '<PropertyGroup><PublishAot>false</PublishAot><PublishAotUsingRuntimePack>false</PublishAotUsingRuntimePack><SelfContained>false</SelfContained><RuntimeIdentifier></RuntimeIdentifier><IsAotCompatible>false</IsAotCompatible></PropertyGroup></Project>')
        project.write_text(source, encoding='utf-8', newline='\n')
    spec = importlib.util.spec_from_file_location('ryu_prepare', ROOT / 'ios/scripts/prepare_core.py')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    helper.SOURCE = DEST
    helper.generate_callback_pointers()
    # Carry forward the reproduced LibHac short-read fix for game inputs.
    stream = (ROOT / 'ios/Overlays/ReadOnlyGameStream.cs').read_text(encoding='utf-8-sig')
    stream = stream.replace('StartupDiagnostics.Write(',
        'Ryujinx.Common.Logging.Logger.Error?.Print(Ryujinx.Common.Logging.LogClass.Loader, ')
    (DEST / 'src/Ryujinx.HLE/Loaders/ReadOnlyGameStream.cs').write_text(stream, encoding='utf-8', newline='\n')
    loader = 'src/Ryujinx.HLE/Loaders/Processes/ProcessLoader.cs'
    edit(loader, 'FileStream stream = new(path, FileMode.Open, FileAccess.Read);',
         'Stream stream = new Ryujinx.HLE.Loaders.ReadOnlyGameStream(path);')
    edit(loader, 'FileStream file = new(path, FileMode.Open, FileAccess.Read);',
         'Stream file = new Ryujinx.HLE.Loaders.ReadOnlyGameStream(path);')
    edit(loader, 'FileStream input = new(path, FileMode.Open);',
         'Stream input = new Ryujinx.HLE.Loaders.ReadOnlyGameStream(path);')
    edit('src/Ryujinx.HLE/Utilities/PartitionFileSystemUtils.cs',
         'FileStream file = File.OpenRead(path);', 'Stream file = new Ryujinx.HLE.Loaders.ReadOnlyGameStream(path);')
    edit('src/Ryujinx.Library/Library.cs', 'private static FileStream OpenFile(int descriptor)',
         'private static Stream OpenFile(int descriptor)')
    edit('src/Ryujinx.Library/Library.cs', 'return new FileStream(safeHandle, FileAccess.ReadWrite);',
         'return new Ryujinx.HLE.Loaders.ReadOnlyGameStream(new FileStream(safeHandle, FileAccess.Read));')
    # Assembly.GetEntryAssembly is null in an embedded NativeAOT dylib.
    for key, value in [('BUILD_VERSION', '1.0.0'), ('BUILD_GIT_HASH', RYU),
                       ('TARGET_RELEASE_CHANNEL_NAME', 'ios-melonx'), ('CONFIG_FILE_NAME', 'Config.json')]:
        edit('src/Ryujinx.Common/ReleaseInformation.cs', '%%RYUJINX_' + key + '%%', value)
    edit('src/Ryujinx.Common/Logging/Targets/ConsoleLogTarget.cs',
         '            Console.ResetColor();\n        }\n    }',
         '            if (!OperatingSystem.IsIOS()) Console.ResetColor();\n        }\n    }')
    # Use a dedicated bundle identity so the existing tested Ryu app stays installed.
    project = 'src/MeloNX/MeloNX.xcodeproj/project.pbxproj'
    edit(project, 'com.stossy11.MeloNX', 'app.ryu.ios.melonx')
    text = (DEST / project).read_text()
    text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 27.0;', text)
    text = re.sub(r'DEVELOPMENT_TEAM = [^;]*;', 'DEVELOPMENT_TEAM = "";', text)
    # Build the engine explicitly. Never invoke the supplied profile-sourcing
    # legacy build target, nor consume a free-signing app ID for the donor.
    text = text.replace('\t\t\t\t4EA2CB242FD924E000BE964F /* PBXTargetDependency */,\n', '')
    text = text.replace('\t\t\t\t4EDA000100000000000A000D /* PBXTargetDependency */,\n', '')
    text = text.replace('\t\t\t\t4EDA000100000000000A000A /* Embed Foundation Extensions */,\n', '')
    (DEST / project).write_text(text, encoding='utf-8', newline='\n')
    info = DEST / 'src/MeloNX/MeloNX/Info.plist'
    with info.open('rb') as stream: data = plistlib.load(stream)
    data['CFBundleDisplayName'] = 'Ryu MeloNX'
    data['CFBundleShortVersionString'] = '1.0.0'
    data['LSApplicationQueriesSchemes'] = sorted(set(data.get('LSApplicationQueriesSchemes', []) + ['stikdebug']))
    with info.open('wb') as stream: plistlib.dump(data, stream)
    # Retain all upstream notices; provenance travels with the app and IPA.
    provenance = dict(melonx=MELO, ryubing=RYU, common_ancestor=BASE, merged_tree=tree,
                      security_fixes=['disabled library callback', 'bounded ZIP extraction'],
                      jit_helper='reviewed BreakpointJIT.S; StikDebug universal.js',
                      native_dependencies='supplied binary dependencies require independent provenance verification')
    (DEST / 'integration-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    for path in (DEST / 'src').rglob('*.cs'):
        if re.search(r'^<<<<<<< |^>>>>>>> ', path.read_text(encoding='utf-8-sig'), re.M):
            raise RuntimeError('Unresolved conflict: ' + str(path))
    print('Prepared MeloNX', MELO, '+ latest Ryubing', RYU)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--offline', action='store_true')
    prepare(parser.parse_args().offline)
