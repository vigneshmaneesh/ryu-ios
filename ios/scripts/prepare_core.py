"""Fetch an immutable upstream tree; apply narrowly checked iOS platform overlays.

Never modifies the supplied source or advances the lock to a moving branch.
An upstream update is a reviewed lock change followed by this script and CI.
"""
import argparse
import hashlib
import io
import json
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


def replace(path, old, new, count=1):
    target = SOURCE / path
    text = target.read_text(encoding="utf-8")
    actual = text.count(old)
    if actual != count:
        raise RuntimeError(f"Upstream adapter conflict: {path}: expected {count} matches, found {actual}")
    target.write_text(text.replace(old, new), encoding="utf-8", newline="\n")


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
        shutil.rmtree(SOURCE)
    SOURCE.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(SOURCE, filter="data")
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
