"""Fail the build if the IPA would be missing a required component or entitlement."""
from pathlib import Path
import plistlib
import struct
import sys


def verify_ios_binary(path, expected_minimum=None):
    """Check the actual Mach-O load commands, rather than trusting the plist."""
    data = path.read_bytes()
    header = struct.unpack_from("<IiiIIIII", data)
    assert header[0] == 0xFEEDFACF, f"Expected a thin 64-bit Mach-O: {path}"
    assert header[1] == 0x0100000C, f"Expected ARM64: {path}"
    offset = 32
    found_platform = False
    for _ in range(header[4]):
        command, size = struct.unpack_from("<II", data, offset)
        assert size >= 8 and offset + size <= len(data), f"Invalid load command: {path}"
        if command == 0x32:  # LC_BUILD_VERSION
            platform, minimum = struct.unpack_from("<II", data, offset + 8)
            assert platform == 2, f"Expected iOS device platform, got {platform}: {path}"
            assert minimum <= (27 << 16), f"Binary requires a newer OS than iOS 27: {path}"
            if expected_minimum is not None:
                assert minimum == expected_minimum, f"Wrong app deployment target: {path}"
            found_platform = True
        offset += size
    assert found_platform, f"Missing iOS platform load command: {path}"


app, entitlements_path = map(Path, sys.argv[1:3])
with (app / "Info.plist").open("rb") as file:
    info = plistlib.load(file)
with entitlements_path.open("rb") as file:
    entitlements = plistlib.load(file)
assert info["MinimumOSVersion"] == "27.0"
assert info["UIDeviceFamily"] == [1, 2]
assert "stikdebug" in info["LSApplicationQueriesSchemes"]
assert entitlements.get("get-task-allow") is True
assert (app / info["CFBundleExecutable"]).stat().st_size > 0
verify_ios_binary(app / info["CFBundleExecutable"], 27 << 16)
framework = app / "Frameworks/RyujinxEmitter.framework"
assert (framework / "RyujinxEmitter").stat().st_size > 0
verify_ios_binary(framework / "RyujinxEmitter")
with (framework / "Info.plist").open("rb") as file:
    framework_info = plistlib.load(file)
assert framework_info["CFBundleExecutable"] == "RyujinxEmitter"
assert (app / "LICENSE.txt").is_file()
core = app / "Frameworks/RyuCore.framework"
verify_ios_binary(core / "RyuCore")
with (core / "Info.plist").open("rb") as file:
    assert plistlib.load(file)["CFBundleExecutable"] == "RyuCore"
assert (app / "upstream.lock.json").is_file()
print("PASS: iOS ARM64 binaries, IPA contents, iPhone/iPad targets, and JIT entitlements.")
