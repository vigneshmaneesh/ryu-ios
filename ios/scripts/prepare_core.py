"""Fetch an immutable upstream tree; apply narrowly checked iOS platform overlays.

Never modifies the supplied source or advances the lock to a moving branch.
An upstream update is a reviewed lock change followed by this script and CI.
"""
import argparse
import hashlib
import io
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "ios/build"
SOURCE = BUILD / "upstream"


def git(*args, capture=False):
    return subprocess.run(["git", *map(str, args)], check=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def remove_build_tree(path):
    def locked_empty_directory(function, name, error):
        # An idle Windows compiler node can retain its working directory. Files
        # must still be removed; retaining an empty directory cannot retain code.
        directory = Path(name)
        if function is os.rmdir and getattr(error, "winerror", 0) == 32 and not any(directory.iterdir()):
            return
        if function is os.rmdir and getattr(error, "winerror", 0) == 145:
            if all(p.is_dir() for p in directory.rglob("*")):
                return
        raise error
    shutil.rmtree(path, onexc=locked_empty_directory)


def replace(path, old, new, count=1):
    target = SOURCE / path
    text = target.read_text(encoding="utf-8")
    actual = text.count(old)
    if actual != count:
        raise RuntimeError(f"Upstream adapter conflict: {path}: expected {count} matches, found {actual}")
    target.write_text(text.replace(old, new), encoding="utf-8", newline="\n")


def generate_callback_pointers():
    # NativeAOT does not synthesize a callable UCO entry point merely because
    # reflection found its metadata. Taking each address at build time roots the
    # actual native callback and preserves its unmanaged calling convention.
    entries = {}
    pattern = re.compile(r"\[UnmanagedCallersOnly\]\s+public static (\w+) (\w+)\(([^)]*)\)")
    tokens = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|@?"(?:""|\\.|[^"\\])*"|\bclass\s+(\w+)|[{}]')
    for path in sorted((SOURCE / "src/ARMeilleure/Instructions").rglob("*.cs")):
        source = path.read_text()
        for match in pattern.finditer(source):
            scopes, depth, pending = [], 0, None
            for token in tokens.finditer(source[:match.start()]):
                if token.group(1):
                    pending = token.group(1)
                elif token.group() == "{":
                    depth += 1
                    if pending:
                        scopes.append((depth, pending))
                        pending = None
                elif token.group() == "}":
                    if scopes and scopes[-1][0] == depth:
                        scopes.pop()
                    depth -= 1
            if not scopes:
                raise RuntimeError(f"Cannot identify callback owner: {path}")
            owner = scopes[-1][1]
            result, name, args = match.groups()
            types = [arg.strip().split()[0] for arg in args.split(",") if arg.strip()]
            signature = ", ".join([*types, result])
            key = f"{owner}.{name}"
            if key in entries:
                raise RuntimeError(f"Ambiguous native callback: {key}")
            entries[key] = f'(nint)(delegate* unmanaged<{signature}>)&{owner}.{name}'
    if not entries or "NativeInterface.GetFunctionAddress" not in entries:
        raise RuntimeError("The upstream native callback surface changed")
    lines = ["using ARMeilleure.Instructions;", "using ARMeilleure.State;", "using System.Reflection;",
             "namespace ARMeilleure.Translation;", "internal static unsafe class AotCallbackPointers", "{",
             "    internal static nint Get(MethodInfo method) => (method.DeclaringType.Name + \".\" + method.Name) switch", "    {"]
    lines += [f'        "{key}" => {value},' for key, value in sorted(entries.items())]
    lines += ["        _ => method.MethodHandle.GetFunctionPointer(),", "    };", "}"]
    (SOURCE / "src/ARMeilleure/Translation/AotCallbackPointers.cs").write_text("\n".join(lines) + "\n", encoding="utf-8")
    replace("src/ARMeilleure/Translation/Delegates.cs", "method.MethodHandle.GetFunctionPointer()", "AotCallbackPointers.Get(method)")
    replace("src/ARMeilleure/Translation/EmitterContext.cs", "info.MethodHandle.GetFunctionPointer()", "AotCallbackPointers.Get(info)")
    print(f"Rooted {len(entries)} native CPU callbacks with static function pointers.")


def add_startup_diagnostics():
    # An optional host hook: absent on desktop, and written through to app
    # storage on iOS so a native fault retains the last constructor checkpoint.
    (SOURCE / "src/Ryujinx.HLE/StartupDiagnostics.cs").write_text('''using System;
namespace Ryujinx.HLE;
public static class StartupDiagnostics
{
    public static Action<string> Checkpoint { get; set; }
    public static void Write(string stage) => Checkpoint?.Invoke(stage);
    // The normal NRO loader waits on this same barrier before running a guest.
    public static void WaitServicesReady(Switch device) => device.System.ServiceTable.WaitServicesReady();
}
''', encoding="utf-8")
    stages = {
        "src/Ryujinx.HLE/Switch.cs": [
            ("            DirtyHacks        =", "Switch: dirty hacks and audio adapter"),
            ("            Memory            =", "Switch: reserving guest RAM"),
            ("            Gpu               =", "Switch: GPU bookkeeping"),
            ("            System            =", "Switch: Horizon kernel"),
            ("            Statistics        =", "Switch: performance statistics"),
            ("            Hid               =", "Switch: HID shared memory / input initialization"),
            ("            Processes         =", "Switch: process loader"),
            ("            TamperMachine     =", "Switch: tamper machine"),
            ("            System.InitializeServices();", "Switch: starting service processes"),
            ("            System.State.SetLanguage", "Switch: applying language / region / clocks"),
            ("            Shared = this;", "Switch: constructor complete"),
        ],
        "src/Ryujinx.HLE/HOS/Horizon.cs": [
            ("            TickSource =", "Horizon: tick source"),
            ("            KernelContext = new", "Horizon: kernel context"),
            ("            State = new", "Horizon: system state"),
            ("            SharedMemoryStorage hidStorage =", "Horizon: committing shared-memory pages"),
            ("            TimeServiceManager.Instance.Initialize", "Horizon: time shared memory"),
            ("            SharedFontManager = new", "Horizon: font / account / capture managers"),
            ("            IRtcManager.GetExternalRtcValue", "Horizon: clocks"),
            ("            DatabaseImpl.Instance.InitializeDatabase", "Horizon: settings database"),
            ("            HostSyncpoint = new", "Horizon: host syncpoints"),
            ("            SurfaceFlinger = new", "Horizon: compositor thread"),
            ("            SmRegistry = new", "Services: registry / SM server"),
            ("            SmServer.InitDone.WaitOne();", "Services: waiting for SM readiness"),
            ("            BsdServer = new", "Services: BSD / filesystem / HID / NV / time / VI / LDN"),
            ("            StartNewServices();", "Services: starting generated Horizon services"),
            ("                KernelStatic.StartInitialProcess", "Services: starting process"),
        ],
        "src/Ryujinx.HLE/HOS/Kernel/KernelContext.cs": [
            ("            Syscall = new", "Kernel: syscall table / resource limits"),
            ("            MemoryManager = new", "Kernel: physical memory regions"),
            ("            LargeMemoryBlockSlabManager =", "Kernel: memory slab managers"),
            ("            CommitMemory(KernelConstants", "Kernel: committing user slab heap"),
            ("            CriticalSection = new", "Kernel: scheduler structures / timer thread"),
            ("            StartPreemptionThread();", "Kernel: starting preemption thread"),
            ("            KernelInitialized = true;", "Kernel: context initialized"),
        ],
    }
    for path, checkpoints in stages.items():
        for prefix, message in checkpoints:
            indentation = prefix[:len(prefix) - len(prefix.lstrip())]
            replace(path, prefix, f'{indentation}Ryujinx.HLE.StartupDiagnostics.Write("{message}");\n{prefix}')


def adapt_vulkan():
    renderer = "src/Ryujinx.Graphics.Vulkan/VulkanRenderer.cs"
    replace(renderer, "IsMoltenVk = OperatingSystem.IsMacOS()", "IsMoltenVk = (OperatingSystem.IsMacOS() || OperatingSystem.IsIOS())")
    replace(renderer, "SupportsMTL31 = OperatingSystem.IsMacOSVersionAtLeast(14);",
            "SupportsMTL31 = OperatingSystem.IsMacOSVersionAtLeast(14) || OperatingSystem.IsIOSVersionAtLeast(17);")
    replace(renderer, "hasDriverProperties && !OperatingSystem.IsMacOS()", "hasDriverProperties && !IsMoltenVk")
    replace(renderer, "public uint ProgramCount { get; set; } = 0;",
            "public uint ProgramCount { get; set; } = 0;\n        public ulong PresentedFrames { get; internal set; }")
    replace("src/Ryujinx.Graphics.Vulkan/MoltenVK/MVKInitialization.cs", '[SupportedOSPlatform("macos")]',
            '[SupportedOSPlatform("macos")]\n    [SupportedOSPlatform("ios")]')
    initialization = "src/Ryujinx.Graphics.Vulkan/VulkanInitialization.cs"
    replace(initialization, "string[] enabledExtensions = requiredExtensions;", '''bool portabilityEnumeration = instanceExtensions.Contains("VK_KHR_portability_enumeration");
            string[] enabledExtensions = portabilityEnumeration
                ? requiredExtensions.Append("VK_KHR_portability_enumeration").Distinct().ToArray()
                : requiredExtensions;''')
    replace(initialization, "PpEnabledExtensionNames = (byte**)ppEnabledExtensions,\n                PpEnabledLayerNames = (byte**)ppEnabledLayers,",
            "Flags = portabilityEnumeration ? InstanceCreateFlags.EnumeratePortabilityBitKhr : 0,\n                PpEnabledExtensionNames = (byte**)ppEnabledExtensions,\n                PpEnabledLayerNames = (byte**)ppEnabledLayers,")
    window = "src/Ryujinx.Graphics.Vulkan/Window.cs"
    replace(window, "                    ulong.MaxValue,", "                    OperatingSystem.IsIOS() ? 250_000_000UL : ulong.MaxValue,")
    replace(window, "                if (acquireResult == Result.ErrorOutOfDateKhr ||",
            "                if (acquireResult == Result.Timeout) return; // Allow iOS lifecycle cancellation.\n\n                if (acquireResult == Result.ErrorOutOfDateKhr ||")
    replace(window, "                _gd.SwapchainApi.QueuePresent(_gd.Queue, in presentInfo);", '''                Result queueResult = _gd.SwapchainApi.QueuePresent(_gd.Queue, in presentInfo);
                if (queueResult != Result.SuboptimalKhr) queueResult.ThrowOnError();
                if (result != Result.SuboptimalKhr) result.ThrowOnError();
                _gd.PresentedFrames++;''')
    replace("src/Ryujinx.Graphics.Vulkan/Shader.cs", "Shaderc api = Shaderc.GetApi();", '''if (OperatingSystem.IsIOS())
                throw new PlatformNotSupportedException("The iOS renderer accepts SPIR-V shaders; the optional GLSL compiler is not packaged.");
            Shaderc api = Shaderc.GetApi();''')


def prepare(offline=False):
    lock = json.loads((ROOT / "ios/upstream.lock.json").read_text())
    revision = lock["revision"]
    if len(revision) != 40 or any(c not in "0123456789abcdef" for c in revision):
        raise ValueError("The lock must contain a full immutable Git commit")
    BUILD.mkdir(parents=True, exist_ok=True)
    cache = BUILD / "upstream-source.git"
    if not cache.exists():
        git("init", "--bare", cache)
    try:
        git("-C", cache, "cat-file", "-e", f"{revision}^{{commit}}")
    except subprocess.CalledProcessError:
        if offline:
            raise RuntimeError("Locked source is absent from the offline cache")
        git("-C", cache, "fetch", "--depth=1", lock["repository"], revision)
    # archive forces blob availability, including when an existing cache is partial.
    archive = git("-C", cache, "archive", "--format=tar", revision, capture=True)
    source_path = SOURCE.resolve()
    if source_path.parent != BUILD.resolve() or source_path.name != "upstream":
        raise RuntimeError("Unsafe build output path")
    if SOURCE.exists():
        remove_build_tree(SOURCE)
    SOURCE.mkdir(exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(SOURCE, filter="data")
    # Roslyn generators run on the build host. Global publish switches from the
    # native library must not turn their netstandard2.0 assemblies into iOS AOT apps.
    for name in ("Ryujinx.HLE.Generators", "Ryujinx.Horizon.Generators", "Ryujinx.Horizon.Kernel.Generators"):
        path = f"src/{name}/{name}.csproj"
        replace(path, '<Project Sdk="Microsoft.NET.Sdk">',
                '<Project Sdk="Microsoft.NET.Sdk" TreatAsLocalProperty="PublishAot;PublishAotUsingRuntimePack;SelfContained;RuntimeIdentifier;IsAotCompatible;SupportedOSPlatformVersion">')
        replace(path, "<PropertyGroup>", "<PropertyGroup>\n        <PublishAot>false</PublishAot>\n        <PublishAotUsingRuntimePack>false</PublishAotUsingRuntimePack>\n        <SelfContained>false</SelfContained>\n        <RuntimeIdentifier></RuntimeIdentifier>\n        <IsAotCompatible>false</IsAotCompatible>\n        <SupportedOSPlatformVersion></SupportedOSPlatformVersion>")
    # Inject a small, opt-in seam into the original assemblies. Desktop behavior
    # remains upstream's when no host supplies a prepared-code allocator.
    replace("src/Ryujinx.Cpu/Jit/JitMemoryAllocator.cs",
            "private readonly MemoryAllocationFlags _jitFlag;",
            "private readonly MemoryAllocationFlags _jitFlag;\n        public static System.Func<ulong, IJitMemoryBlock> PreparedCodeAllocator { get; set; }")
    replace("src/Ryujinx.Cpu/Jit/JitMemoryAllocator.cs",
            "public IJitMemoryBlock Reserve(ulong size) => new JitMemoryBlock(size, MemoryAllocationFlags.Reserve | _jitFlag);",
            "public IJitMemoryBlock Reserve(ulong size) => _jitFlag != MemoryAllocationFlags.None && PreparedCodeAllocator != null\n            ? PreparedCodeAllocator(size)\n            : new JitMemoryBlock(size, MemoryAllocationFlags.Reserve | _jitFlag);")
    interface = SOURCE / "src/ARMeilleure/Memory/IPreparedJitMemoryBlock.cs"
    interface.write_text('''using System;
namespace ARMeilleure.Memory;
// Host publishes code through a writable alias while Pointer stays executable.
public interface IPreparedJitMemoryBlock : IJitMemoryBlock
{
    void Write(ulong offset, ReadOnlySpan<byte> code);
}
''', encoding="utf-8")
    for path in ("src/ARMeilleure/Translation/Cache/JitCache.cs",
                 "src/Ryujinx.Cpu/LightningJit/Cache/JitCache.cs"):
        replace(path, "if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())",
                "if (_jitRegions[0].Block is not IPreparedJitMemoryBlock && !OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())")
        replace(path, "if (OperatingSystem.IsMacOS() && RuntimeInformation.ProcessArchitecture == Architecture.Arm64)",
                "if (GetRegion(funcOffset).Block is IPreparedJitMemoryBlock prepared)\n                {\n                    prepared.Write((ulong)(funcOffset % (int)CacheSize), code);\n                }\n                else if (OperatingSystem.IsMacOS() && RuntimeInformation.ProcessArchitecture == Architecture.Arm64)")
    generate_callback_pointers()
    add_startup_diagnostics()
    adapt_vulkan()
    # iOS/tvOS ConsolePal supports writing to NSLog, but colour APIs throw.
    # An exception on the upstream async logging thread terminates the process.
    console = "src/Ryujinx.Common/Logging/Targets/ConsoleLogTarget.cs"
    replace(console, "Console.ForegroundColor = GetLogColor(args.Level);",
            "if (!OperatingSystem.IsIOS() && !OperatingSystem.IsTvOS())\n                Console.ForegroundColor = GetLogColor(args.Level);")
    replace(console, "Console.ResetColor();",
            "if (!OperatingSystem.IsIOS() && !OperatingSystem.IsTvOS())\n                Console.ResetColor();", 2)
    replace("src/Ryujinx.Graphics.Gpu/Engine/MME/Macro.cs", "else if (GraphicsConfig.EnableMacroJit)",
            "else if (System.Runtime.CompilerServices.RuntimeFeature.IsDynamicCodeSupported && GraphicsConfig.EnableMacroJit)")
    replace("src/ARMeilleure/CodeGen/Arm64/HardwareCapabilities.cs",
            "if (OperatingSystem.IsMacOS())", "if (OperatingSystem.IsMacOS() || OperatingSystem.IsIOS())")
    replace("src/ARMeilleure/CodeGen/Arm64/HardwareCapabilities.cs",
            '[SupportedOSPlatform("macos")]', '[SupportedOSPlatform("macos")]\n        [SupportedOSPlatform("ios")]')
    replace("src/Ryujinx.Memory/MemoryManagement.cs",
            "OperatingSystem.IsLinux() || OperatingSystem.IsMacOS()",
            "OperatingSystem.IsLinux() || OperatingSystem.IsMacOS() || OperatingSystem.IsIOS()", 12)
    for path in ("src/Ryujinx.Memory/MemoryManagementUnix.cs", "src/Ryujinx.Memory/MemoryManagerUnixHelper.cs"):
        replace(path, '[SupportedOSPlatform("macos")]', '[SupportedOSPlatform("macos")]\n    [SupportedOSPlatform("ios")]')
        text = (SOURCE / path).read_text()
        replace(path, "OperatingSystem.IsMacOS()", "(OperatingSystem.IsMacOS() || OperatingSystem.IsIOS())", text.count("OperatingSystem.IsMacOS()"))
    # MADV_REMOVE=9 is Linux-specific; Darwin MADV_DONTNEED releases anonymous pages.
    replace("src/Ryujinx.Memory/MemoryManagementUnix.cs", "madvise(address, size, MADV_REMOVE)",
            "madvise(address, size, OperatingSystem.IsIOS() ? MADV_DONTNEED : MADV_REMOVE)")
    files = {}
    for path in sorted((SOURCE / "src").rglob("*.cs")):
        # Hashes cover generated adapter output too, so diagnostics identify its source.
        files[path.relative_to(SOURCE).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    manifest = {"upstream": revision, "adapterAbi": lock["adapterAbi"], "files": files}
    (BUILD / "core-source-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Prepared locked core {revision}; {len(files)} C# sources, checked platform overlays.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    prepare(args.offline)
