#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/ios/build/graphics-simulator"
app="$out/GraphicsChecks.app"
mkdir -p "$app/Frameworks" "$out/core"
python3 "$root/ios/scripts/prepare_native.py" --validation
molten="$root/ios/build/native-dependencies/MoltenVK/MoltenVK"
cp -R "$molten/dynamic/MoltenVK.xcframework/ios-arm64_x86_64-simulator/MoltenVK.framework" "$app/Frameworks/"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SDKROOT="$sdk" dotnet publish "$root/ios/Runtime/RyuCore.csproj" \
    -c Release -r iossimulator-arm64 -o "$out/core" \
    -p:PublishAot=true -p:PublishAotUsingRuntimePack=true -p:SupportedOSPlatformVersion=27.0 \
    --configfile "$root/ios/build/upstream/nuget.config"
cp "$out/core/RyuCore.dylib" "$app/Frameworks/RyuCore.dylib"
install_name_tool -id '@rpath/RyuCore.dylib' "$app/Frameworks/RyuCore.dylib"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -isysroot "$sdk" \
    -std=c11 -O2 -Wall -Wextra -Werror -I "$molten/include" \
    -c "$root/ios/Native/MetalSurface.c" -o "$out/MetalSurface.o"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -isysroot "$sdk" \
    -std=c11 -O2 -Wall -Wextra -Werror -I "$root/ios/Native" \
    -c "$root/ios/Native/CoreWorker.c" -o "$out/CoreWorker.o"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -isysroot "$sdk" \
    -std=gnu11 -fobjc-arc -O2 -Wall -Wextra -Werror -I "$root/ios/Native" \
    -F "$app/Frameworks" -framework MoltenVK -framework UIKit -framework QuartzCore -framework Metal \
    "$root/ios/Native/HostGraphicsChecks.m" "$out/CoreWorker.o" "$out/MetalSurface.o" \
    "$app/Frameworks/RyuCore.dylib" -Wl,-rpath,@executable_path/Frameworks -o "$app/GraphicsChecks"
python3 - "$app" <<'PY'
import plistlib, sys
from pathlib import Path
info = dict(CFBundleIdentifier="app.ryu.ios.GraphicsChecks", CFBundleName="GraphicsChecks",
    CFBundleExecutable="GraphicsChecks", CFBundlePackageType="APPL", CFBundleVersion="1",
    CFBundleShortVersionString="1.0", MinimumOSVersion="27.0", LSRequiresIPhoneOS=True,
    UIDeviceFamily=[1, 2], UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait"],
    UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False), UILaunchScreen={})
(Path(sys.argv[1]) / "Info.plist").write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$app/Frameworks/RyuCore.dylib"
codesign --force --sign - "$app/Frameworks/MoltenVK.framework"
codesign --force --sign - "$app"
xcrun --sdk macosx swiftc "$root/ios/Native/GraphicsScreenshotCheck.swift" \
    -framework CoreGraphics -framework ImageIO -o "$out/GraphicsScreenshotCheck"

python3 -c 'import subprocess,sys; subprocess.run(["xcrun","simctl","list","--json"],stdout=open(sys.argv[1],"w"),check=True,timeout=180)' "$out/inventory.json"
selection="$(python3 "$root/ios/scripts/select_simulator.py" "$out/inventory.json")"
IFS=$'\t' read -r runtime device_type <<< "$selection"
device="$(python3 -c 'import subprocess,sys; print(subprocess.check_output(["xcrun","simctl","create","RyuRendererRegression",sys.argv[1],sys.argv[2]],text=True,timeout=180).strip())' "$device_type" "$runtime")"
trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1 || true; xcrun simctl delete "$device" >/dev/null 2>&1 || true' EXIT
echo "Booting graphics simulator $device / $runtime"
python3 -c 'import subprocess,sys; subprocess.run(["xcrun","simctl","boot",sys.argv[1]],check=True,timeout=420)' "$device"
python3 -c 'import subprocess,sys; subprocess.run(["xcrun","simctl","bootstatus",sys.argv[1],"-b"],check=True,timeout=600)' "$device"
python3 "$root/ios/scripts/check_graphics_app.py" "$device" "$app" "$out"
"$out/GraphicsScreenshotCheck" "$out/renderer-screen.png"
