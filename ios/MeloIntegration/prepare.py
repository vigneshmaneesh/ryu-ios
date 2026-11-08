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
    # Keep original archive/callback/native libraries; apply the focused JIT flow fix.
    overlay = HERE / 'overlay'
    if overlay.exists():
        shutil.copytree(overlay, DEST, dirs_exist_ok=True)
    # Upstream moved sparse-table selection out of AddressTable.CreateForArm;
    # retain MeloNX's iOS restriction at both new call sites.
    for backend in ('Jit/JitCpuContext.cs', 'LightningJit/LightningJitCpuContext.cs'):
        edit('src/Ryujinx.Cpu/' + backend,
             'bool sparse = memory.Type is not MemoryManagerType.SoftwareMmu and not MemoryManagerType.SoftwarePageTable;\n            IAddressTable<ulong> functionTable = sparse ? SparseAddressTable<ulong>.CreateForArm(for64Bit) : AddressTable<ulong>.CreateForArm(for64Bit);',
             'IAddressTable<ulong> functionTable = ArmAddressTableFactory.Create(memory.Type, for64Bit, System.OperatingSystem.IsIOS());')
    swift = 'src/MeloNX/MeloNX/'
    apply_jit_flow_fix(swift)
    apply_guest_ram_fix(swift)
    # The host menu is always reachable above virtual controls. Replace the old
    # hide switch in global/per-game settings, including existing saved values.
    for settings_view in ('UI/Main/Settings/SettingsView.swift', 'UI/Main/Settings/PerGameSettings.swift'):
        edit(swift + settings_view,
             '''                NativeToggleRow("Menu Button (in-game)", icon: "arrow.left.circle",
                                isOn: nativeSettingsManager.showScreenShotButton(true).projectedValue,
                                info: "Shows an in-game menu button to exit, lock orientation (iPhone only), change aspect ratio, or change controllers.")''',
             '                LabeledContent("Menu Button (in-game)", value: "Always visible")')
    path = DEST / (swift + 'Core/RyujinxController.swift')
    source = path.read_text(encoding='utf-8-sig')
    # Retain MeloNX's memory-capability gates. The final sideloader must grant
    # the requested entitlement, rather than letting startup fail deep in mmap.
    assert '        if !hasIncreasedMemoryLimitEntitlement {' in source
    assert '        if !hasExtendedVirtualAddressingEntitlement &&' in source
    source = source.replace('        if !hasIncreasedMemoryLimitEntitlement {',
                            '        print("[Memory] Capabilities: increased-memory-limit=\\(hasIncreasedMemoryLimitEntitlement), extended-virtual-addressing=\\(hasExtendedVirtualAddressingEntitlement)")\n        if !hasIncreasedMemoryLimitEntitlement {', 1)
    source = source.replace('return state == .entitlement',
                            'return state == .entitlement || state == .extendedEntitlement')
    source = source.replace('        Thread.detachNewThread {', '        let gameThread = Thread {', 1)
    needle = '\n        }\n    }\n    \n    \n    func redirectStdIOToFile()'
    assert needle in source
    source = source.replace(needle, '\n        }\n        gameThread.name = "Ryu emulation"\n        gameThread.stackSize = 8 * 1024 * 1024\n        gameThread.start()\n    }\n    \n    \n    func redirectStdIOToFile()', 1)
    path.write_text(source, encoding='utf-8', newline='\n')
    edit(swift + 'UI/Main/ContentView.swift',
         'MeloNX **REQUIRES** the Increased Memory Limit entitlement, Please follow the instructions on how to Install MeloNX and Enable the Entitlement.',
         'iOS has not granted this installation the Increased Memory Limit permission. Reinstall with AltStore Classic 2.2 or later, which supports requesting this permission.')
    edit(swift + 'UI/Main/ContentView.swift',
         'https://git.ryujinx.app/projects/MeloNX#how-to-install',
         'https://faq.altstore.io/release-notes/altstore')
    edit(swift + 'UI/Main/ContentView.swift',
         'The Extended Virtual Addressing entitlement is required for your device, Please read the Information on how to Install MeloNX and Enable the **PAID** Entitlement.',
         'iOS could not reserve the address space needed to start emulation. This installation does not have the Extended Virtual Addressing permission. Check the signing capabilities used to install the app.')
    # Provider selection is an integration default, not a JIT implementation patch.
    for path in (DEST / swift).rglob('*.swift'):
        source = path.read_text(encoding='utf-8-sig')
        updated = source.replace('jitProvider(JITProvider.disabled)', 'jitProvider(JITProvider.stikdebug)')
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
    # Retain stock MeloNX identities so AltStore can reuse its existing app and
    # RAM helper registrations. AltStore adds the user's team suffix itself.
    project = 'src/MeloNX/MeloNX.xcodeproj/project.pbxproj'
    text = (DEST / project).read_text()
    assert text.count('PRODUCT_BUNDLE_IDENTIFIER = com.stossy11.MeloNX;') == 2
    assert text.count('PRODUCT_BUNDLE_IDENTIFIER = com.stossy11.MeloNX.RamDonor;') == 2
    text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 27.0;', text)
    text = re.sub(r'DEVELOPMENT_TEAM = [^;]*;', 'DEVELOPMENT_TEAM = "";', text)
    # Build the engine explicitly. Never invoke the supplied profile-sourcing
    # legacy build target. Retain the stock RAM donor target and embedding phase.
    text = text.replace('\t\t\t\t4EA2CB242FD924E000BE964F /* PBXTargetDependency */,\n', '')
    assert '\t\t\t\t4EDA000100000000000A000D /* PBXTargetDependency */,\n' in text
    assert '\t\t\t\t4EDA000100000000000A000A /* Embed Foundation Extensions */,\n' in text
    (DEST / project).write_text(text, encoding='utf-8', newline='\n')
    info = DEST / 'src/MeloNX/MeloNX/Info.plist'
    with info.open('rb') as stream: data = plistlib.load(stream)
    data['CFBundleDisplayName'] = 'Ryu MeloNX'
    data['CFBundleShortVersionString'] = '1.0.0'
    data['LSApplicationQueriesSchemes'] = sorted(set(data.get('LSApplicationQueriesSchemes', []) + ['stikdebug', 'stikjit']))
    with info.open('wb') as stream: plistlib.dump(data, stream)
    # Retain all upstream notices; provenance travels with the app and IPA.
    provenance = dict(melonx=MELO, ryubing=RYU, common_ancestor=BASE, merged_tree=tree,
                      bundle_id='com.stossy11.MeloNX',
                      sideload_identity='stock MeloNX base IDs; AltStore adds account suffix and reuses matching registrations',
                      security_fixes=[],
                      review_runtime_changes='reverted at user request',
                      jit_helper='original BreakpointJIT.framework; StikDebug universal.js with process-local readiness',
                      jit_flow='single activation handoff, explicit retry, cancelled view polling',
                      cpu_tables='multi-level on iOS for both CPU backends; no 1 TiB sparse reservation',
                      in_game_menu='always-visible native Menu above loading/video/virtual controls; independent of saved hide setting and touch reveal',
                      guest_ram='stock MeloNX allocation flags; startup rollback and error details',
                      ram_donor='stock MeloNXRamDonor.appex, com.stossy11.MeloNX.RamDonor',
                      signing='ad-hoc entitlement request for AltStore re-signing; increased-memory-limit and get-task-allow; device grants must be verified after installation',
                      molten_vk='original MeloNX bundled libMoltenVK.dylib',
                      native_dependencies='supplied binary dependencies require independent provenance verification')
    (DEST / 'integration-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    for path in (DEST / 'src').rglob('*.cs'):
        if re.search(r'^<<<<<<< |^>>>>>>> ', path.read_text(encoding='utf-8-sig'), re.M):
            raise RuntimeError('Unresolved conflict: ' + str(path))
    print('Prepared MeloNX', MELO, '+ latest Ryubing', RYU)

def apply_guest_ram_fix(swift):
    path = 'src/Ryujinx.HLE/Switch.cs'
    edit(path, '''            MemoryAllocationFlags memoryAllocationFlags = OperatingSystem.IsIOS() ||
                    configuration.MemoryManagerMode == MemoryManagerMode.SoftwarePageTable
                ? MemoryAllocationFlags.None
                : MemoryAllocationFlags.Reserve | MemoryAllocationFlags.Mirrorable;''',
         '            using var startup = new StartupResourceScope();')
    edit(path, 'new CompatLayerHardwareDeviceDriver(Configuration.AudioDeviceDriver);',
         'startup.Track(new CompatLayerHardwareDeviceDriver(Configuration.AudioDeviceDriver));')
    edit(path, 'new MemoryBlock(Configuration.MemoryConfiguration.DramSize, memoryAllocationFlags);',
         'startup.Track(GuestRamAllocator.Create(Configuration.MemoryConfiguration.DramSize, configuration.MemoryManagerMode, OperatingSystem.IsIOS()));')
    edit(path, 'new GpuContext(Configuration.GpuRenderer, DirtyHacks);',
         'startup.Track(new GpuContext(Configuration.GpuRenderer, DirtyHacks));')
    edit(path, 'new HOS.Horizon(this);', 'startup.Track(new HOS.Horizon(this));')
    edit(path, '            Shared = this;', '            startup.Commit();\n            Shared = this;')
    edit(path, '        public DirtyHacks DirtyHacks { get; }',
         '        private int _disposed;\n        public DirtyHacks DirtyHacks { get; }')
    edit(path, '            if (disposing)\n            {',
         '            if (disposing && global::System.Threading.Interlocked.Exchange(ref _disposed, 1) == 0)\n            {')
    edit(path, '                FileSystem.Dispose();',
         '                if (!OperatingSystem.IsIOS()) FileSystem.Dispose();')
    library = 'src/Ryujinx.Library/Library.cs'
    edit(library, 'using CommandLine;', 'using CommandLine;\nusing Ryujinx.Common;')
    edit(library, '                Options managed = OptionsNativeHelper.FromNative(nativeOptions);',
         '                StartupErrors.Clear();\n                Options managed = OptionsNativeHelper.FromNative(nativeOptions);')
    edit(library, '                Console.WriteLine(e.ToString());\n                return -1;',
         '                StartupErrors.Set(e);\n                Console.WriteLine(e.ToString());\n                return -1;')
    edit(library, '            _inputManager.Dispose();',
         '            if (!OperatingSystem.IsIOS()) _inputManager.Dispose();')
    edit(library, '''            _libHacHorizonManager = new LibHacHorizonManager();
            _libHacHorizonManager.InitializeFsServer(_virtualFileSystem);
            _libHacHorizonManager.InitializeArpServer();
            _libHacHorizonManager.InitializeBcatServer();
            _libHacHorizonManager.InitializeSystemClients();''',
         '''            if (!OperatingSystem.IsIOS())
            {
                _libHacHorizonManager = new LibHacHorizonManager();
                _libHacHorizonManager.InitializeFsServer(_virtualFileSystem);
                _libHacHorizonManager.InitializeArpServer();
                _libHacHorizonManager.InitializeBcatServer();
                _libHacHorizonManager.InitializeSystemClients();
            }''')
    edit(library, '                LoadApplication(option);',
         '                if (!LoadApplication(option)) throw new InvalidOperationException("The title loader could not start this game. See the session log for its load error.");')
    edit(library, '            _emulationContext.Dispose();\n            _window.Dispose();', '')
    p = DEST / library
    source = p.read_text(encoding='utf-8-sig')
    start = source.index('        private static bool LoadApplication(Options options)')
    end = source.index('        // GameInfo', start)
    block = source[start:end]
    block = block.replace('            string path = options.InputPath;',
        '            using var startup = new StartupResourceScope();\n            startup.Defer(() => { _emulationContext = null; _window = null; });\n            string path = options.InputPath;')
    block = block.replace('WindowBase window = CreateWindow(options);',
        'WindowBase window = startup.Track(CreateWindow(options));')
    block = block.replace('IRenderer renderer = CreateRenderer(options, window);',
        'IRenderer renderer = startup.Track(CreateRenderer(options, window));')
    block = block.replace('            _emulationContext = InitializeEmulationContext(window, renderer, options);',
        '''            _emulationContext = null;
            Switch context = InitializeEmulationContext(window, renderer, options);
            _emulationContext = context;
            startup.Release(renderer); // Owned by context.Gpu after construction.
            startup.Defer(() => CleanupSession(context));''')
    block = block.replace('_emulationContext.Dispose(); ', '').replace('                _emulationContext.Dispose();\n', '').replace('                                _emulationContext.Dispose();\n', '')
    assert 'startup.Release(renderer)' in block and '_emulationContext.Dispose();' not in block
    helper = '''        private static void CleanupSession(Switch context)
        {
            void Release(string name, Action action)
            {
                try { action(); }
                catch (ObjectDisposedException) { }
                catch (Exception error) { Console.WriteLine($"[Cleanup] {name}: {error.Message}"); }
            }
            // Stop guest CPU/service threads before releasing GPU resources,
            // then release guest RAM. Keep app-owned files/input available.
            Release("processes", context.Processes.ClearAllProcesses);
            Release("kernel", context.System.Dispose);
            Release("GPU", context.DisposeGpu);
            Release("guest RAM/audio", context.Dispose);
            Console.WriteLine("[Cleanup] Guest session released.");
        }

'''
    source = source[:start] + block + helper + source[end:]
    p.write_text(source, encoding='utf-8', newline='\n')
    window = 'src/Ryujinx.Library/Window/WindowBase.cs'
    # Exit requests stop; resource disposal belongs to the owning session after
    # the GPU worker has finished, not to the UI caller issuing the stop.
    edit(window, '            Device.Dispose();\n\n            if (_isStopped)',
         '            if (_isStopped)')
    edit(library, '                _window.Exit();\n                _emulationContext.Dispose();',
         '                _window.Exit();')
    edit(window, '        private bool _isStopped;', '        private bool _isStopped;\n        private bool _disposed;')
    edit(window, '            if (disposing)\n            {',
         '            if (disposing && !_disposed)\n            {\n                _disposed = true;')
    # Expose the managed exception text to the native UI instead of only -1.
    bridge = swift + 'Core/Ryujinx.swift'
    edit(bridge, '    static func stopEmulation() {', '''    static var lastStartupError: String {
        var buffer = [CChar](repeating: 0, count: 4096)
        _ = buffer.withUnsafeMutableBufferPointer {
            MeloNX.copy_last_startup_error($0.baseAddress, Int32($0.count))
        }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    static func stopEmulation() {''')
    with (DEST / bridge).open('a', encoding='utf-8', newline='\n') as target:
        target.write('\n@_silgen_name("copy_last_startup_error")\nfileprivate func copy_last_startup_error(_ buffer: UnsafeMutablePointer<CChar>?, _ capacity: Int32) -> Int32\n')
    edit(swift + 'Core/RyujinxController.swift', 'self.isRunning = .crashed(result: "Code: \\(response)")',
         'let detail = Ryujinx.lastStartupError\n                    self.isRunning = .crashed(result: detail.isEmpty ? "Code: \\(response)" : detail)')

def apply_jit_flow_fix(swift):
    # The original framework uses BRK 0xf00d/x16=1. Select its matching
    # StikDebug script explicitly, with the current process and bundle ID.
    path = DEST / (swift + 'Common/JIT/EnableJIT.swift')
    source = path.read_text(encoding='utf-8-sig')
    start = source.index('        var urlScheme: String = "stikjit://enable-jit"')
    end = source.index('\n    }\n}', start)
    source = source[:start] + '''        let legacyScript = ProcessInfo.processInfo.hasTXM ? nil : script
        guard let launchURL = JITSessionState.stikDebugURL(
            bundleIdentifier: bundle, pid: getpid(), legacyScript: legacyScript
        ) else {
            jitSessionState.activationFailed()
            return
        }
        openURL(launchURL)''' + source[end:]
    source = source.replace('static func enableJIT(_ provider: JITProvider) {',
        'static func enableJIT(_ provider: JITProvider, explicitRetry: Bool = false) {')
    source = source.replace('        self.provider = provider\n',
        '        guard jitSessionState.beginActivation(explicitRetry: explicitRetry) else { return }\n        self.provider = provider\n')
    source = source.replace('completionHandler: nil)',
        'completionHandler: { opened in\n            if !opened { Task { @MainActor in jitSessionState.activationFailed() } }\n        })')
    path.write_text(source, encoding='utf-8', newline='\n')
    path = DEST / (swift + 'Common/JITChecker.swift')
    source = path.read_text(encoding='utf-8-sig')
    start = source.index('func jitEnabled() -> Bool {')
    end = source.index('\nfunc checkDebugged()', start)
    source = source[:start] + '''let jitSessionState = JITSessionState()

func jitEnabled() -> Bool {
    if jitSessionState.isReady { return true }
    let attached = checkDebugged()
    return jitSessionState.checkReady(debuggerAttached: attached) {
        if #available(iOS 19, *) {
            return RyujinxController.attemptToMapDualMapping()
        }
        return allocateTest()
    }
}
''' + source[end:]
    source = source.replace('var flags: Int = 0', 'var flags: UInt32 = 0')
    source = source.replace('usersize: Int32) -> Int32', 'usersize: Int) -> Int32')
    source = source.replace('Int32(MemoryLayout.size(ofValue: flags))', 'MemoryLayout<UInt32>.size')
    source = source.replace('(flags & Int(CS_DEBUGGED))', '(flags & UInt32(CS_DEBUGGED))')
    path.write_text(source, encoding='utf-8', newline='\n')
    path = DEST / (swift + 'UI/Main/ContentView.swift')
    source = path.read_text(encoding='utf-8-sig')
    start = source.index('            if ryujinxController.lastGameLaunched == nil {')
    end = source.index('            ryujinxController.loadGames()', start)
    source = source[:start] + '            _ = jitEnabled()\n\n' + source[end:]
    path.write_text(source, encoding='utf-8', newline='\n')
    path = DEST / (swift + 'UI/Main/NoJITView.swift')
    source = path.read_text(encoding='utf-8-sig')
    source = source.replace('            Button("Go Back") {', '''            Button("Retry JIT activation") {
                EnableJIT.enableJIT(nativeSettingsManager.jitProvider(JITProvider.disabled).value,
                                    explicitRetry: true)
            }
            Text("Enable JIT in StikDebug, then return here. If memory preparation fails, retry explicitly; the app will stay here.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Go Back") {''')
    start = source.index('        .onAppear {\n            pulseAnimation = true')
    source = source[:start] + '''        .task(id: game.titleId) { @MainActor in
            pulseAnimation = true
            EnableJIT.enableJIT(nativeSettingsManager.jitProvider(JITProvider.disabled).value)
            while !Task.isCancelled {
                guard case .started(let pendingGame, .noJIT) = ryujinxController.isRunning,
                      pendingGame.titleId == game.titleId else { return }
                if jitEnabled() {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        ryujinxController.startGame(game)
                    }
                    return
                }
                do { try await Task.sleep(nanoseconds: 250_000_000) }
                catch { return }
            }
        }
    }
}
'''
    path.write_text(source, encoding='utf-8', newline='\n')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--offline', action='store_true')
    prepare(parser.parse_args().offline)
