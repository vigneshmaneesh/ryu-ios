"""Prepare the native app and NativeAOT framework metadata, without external packages."""
from pathlib import Path
import plistlib
import shutil
import sys

root, output = map(Path, sys.argv[1:3])
version = sys.argv[3]
app = output / "Payload/RyuJIT.app"
with (root / "ios/App/Info.plist").open("rb") as file:
    info = plistlib.load(file)
info["CFBundleVersion"] = version
with (app / "Info.plist").open("wb") as file:
    plistlib.dump(info, file)
framework = app / "Frameworks/RyujinxEmitter.framework"
with (framework / "Info.plist").open("wb") as file:
    plistlib.dump({
        "CFBundleIdentifier": "app.ryu.ios.emitter",
        "CFBundleExecutable": "RyujinxEmitter",
        "CFBundleName": "RyujinxEmitter",
        "CFBundlePackageType": "FMWK",
        "CFBundleShortVersionString": "0.8.0",
        "CFBundleVersion": version,
        "MinimumOSVersion": "27.0",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
    }, file)
shutil.copyfile(root / "LICENSE.txt", app / "LICENSE.txt")
core = app / "Frameworks/RyuCore.framework"
with (core / "Info.plist").open("wb") as file:
    plistlib.dump({
        "CFBundleIdentifier": "app.ryu.ios.core",
        "CFBundleExecutable": "RyuCore",
        "CFBundleName": "RyuCore",
        "CFBundlePackageType": "FMWK",
        "CFBundleShortVersionString": "0.8.0",
        "CFBundleVersion": version,
        "MinimumOSVersion": "27.0",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
    }, file)
shutil.copyfile(root / "ios/upstream.lock.json", app / "upstream.lock.json")
shutil.copyfile(root / "ios/build/upstream/distribution/legal/THIRDPARTY.md", app / "ThirdParty/Ryubing-THIRDPARTY.md")
shutil.copyfile(root / "ios/ThirdParty/Silk.NET-LICENSE.txt", app / "ThirdParty/Silk.NET-LICENSE.txt")
for notice in (root / "ios/ThirdParty").glob("*.txt"):
    shutil.copyfile(notice, app / "ThirdParty" / notice.name)
