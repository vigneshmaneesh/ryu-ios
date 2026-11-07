"""Fail the build if the IPA would be missing a required component or entitlement."""
from pathlib import Path
import plistlib
import sys

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
framework = app / "Frameworks/RyujinxEmitter.framework"
assert (framework / "RyujinxEmitter").stat().st_size > 0
with (framework / "Info.plist").open("rb") as file:
    framework_info = plistlib.load(file)
assert framework_info["CFBundleExecutable"] == "RyujinxEmitter"
assert (app / "LICENSE.txt").is_file()
print("PASS: IPA contents, iPhone/iPad targets, and JIT entitlements.")
