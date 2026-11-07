#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root/ios"
echo "iOS build SDK: $(dotnet --version)"
out="$root/ios/build"
app="$out/Payload/RyuJIT.app"
framework="$app/Frameworks/RyujinxEmitter.framework"
deployment_target=27.0

if [[ "$(uname -s)" != Darwin ]]; then
    echo "An Apple SDK on macOS is required. Use the public GitHub Actions workflow."
    exit 1
fi
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
export SDKROOT="$sdk"
if [[ "${sdk_version%%.*}" -lt 27 ]]; then
    echo "Select Xcode 27 or newer; the selected iOS SDK is $sdk_version."
    exit 1
fi
mkdir -p "$framework" "$out/native" "$out/managed" "$out/macos"
core_framework="$app/Frameworks/RyuCore.framework"
mkdir -p "$core_framework" "$out/core-macos" "$out/core-ios"
python3 "$root/ios/scripts/prepare_core.py"
python3 "$root/ios/scripts/prepare_native.py" --validation
molten_root="$out/native-dependencies/MoltenVK/MoltenVK"
cp -R "$molten_root/dynamic/MoltenVK.xcframework/ios-arm64/MoltenVK.framework" "$app/Frameworks/"
mkdir -p "$app/ThirdParty"
cp "$out/native-dependencies/MoltenVK/LICENSE" "$app/ThirdParty/MoltenVK-LICENSE.txt"

extended="${RYU_EXTENDED_CHECKS:-0}"
if [[ "$extended" == 1 ]]; then
dotnet run --project "$root/ios/EmitterChecks/EmitterChecks.csproj" -c Release
fi

# Run actual translated guest code and reverse managed callbacks in NativeAOT on
# the Apple Silicon host before producing the iOS framework. No simulator substitute.
mac_sdk="$(xcrun --sdk macosx --show-sdk-path)"
if [[ "$extended" == 1 ]]; then
SDKROOT="$mac_sdk" dotnet publish "$root/ios/ManagedEmitter/RyujinxEmitter.csproj" \
    -c Release -r osx-arm64 -o "$out/macos" -p:PublishAot=true
xcrun --sdk macosx clang -arch arm64 -isysroot "$mac_sdk" -mmacosx-version-min=14.0 \
    -std=c11 -O2 -Wall -Wextra -Werror -I "$root/ios/Native" \
    "$root/ios/Native/HostGuestChecks.c" "$out/macos/RyujinxEmitter.dylib" \
    -Wl,-rpath,"$out/macos" -o "$out/macos/HostGuestChecks"
codesign --force --sign - --entitlements "$root/ios/Native/HostJIT.entitlements" "$out/macos/HostGuestChecks"
"$out/macos/HostGuestChecks"
fi

# Compile and execute the entire upstream CPU and real memory manager with the
# same prepared-code allocator used on iOS, including multi-threaded callbacks.
SDKROOT="$mac_sdk" dotnet publish "$root/ios/Runtime/RyuCore.csproj" \
    -c Release -r osx-arm64 -o "$out/core-macos" -p:PublishAot=true \
    --configfile "$out/upstream/nuget.config"
if [[ "$extended" == 1 ]]; then
xcrun --sdk macosx clang -arch arm64 -isysroot "$mac_sdk" -mmacosx-version-min=14.0 \
    -std=c11 -O2 -Wall -Wextra -Werror -I "$root/ios/Native" \
    "$root/ios/Native/HostCoreChecks.c" "$out/core-macos/RyuCore.dylib" \
    -Wl,-rpath,"$out/core-macos" -o "$out/core-macos/HostCoreChecks"
codesign --force --sign - --entitlements "$root/ios/Native/HostJIT.entitlements" "$out/core-macos/HostCoreChecks"
"$out/core-macos/HostCoreChecks" "$out/core-services"
fi

# Smoke-boot the bundled graphics NRO once through the real CPU and GPU.
# The broader conformance suite is optional to keep normal builds focused.
mac_molten="$molten_root/dynamic/MoltenVK.xcframework/macos-arm64_x86_64"
codesign --force --sign - "$mac_molten/MoltenVK.framework"
xcrun --sdk macosx clang -arch arm64 -isysroot "$mac_sdk" -mmacosx-version-min=14.0 \
    -std=c11 -O2 -Wall -Wextra -Werror -I "$molten_root/include" \
    -c "$root/ios/Native/MetalSurface.c" -o "$out/native/MetalSurface-mac.o"
xcrun --sdk macosx clang -arch arm64 -isysroot "$mac_sdk" -mmacosx-version-min=14.0 \
    -std=c11 -O2 -Wall -Wextra -Werror -I "$root/ios/Native" \
    -c "$root/ios/Native/CoreWorker.c" -o "$out/native/CoreWorker-mac.o"
xcrun --sdk macosx clang -arch arm64 -isysroot "$mac_sdk" -mmacosx-version-min=14.0 \
    -std=gnu11 -fobjc-arc -DRYU_GUEST_SMOKE -O2 -Wall -Wextra -Werror -I "$root/ios/Native" \
    -F "$mac_molten" -framework MoltenVK -framework Cocoa -framework QuartzCore -framework Metal \
    "$root/ios/Native/HostGraphicsChecks.m" "$out/native/CoreWorker-mac.o" "$out/native/MetalSurface-mac.o" \
    "$out/core-macos/RyuCore.dylib" -Wl,-rpath,"$out/core-macos" -Wl,-rpath,"$mac_molten" \
    -o "$out/core-macos/HostGraphicsChecks"
codesign --force --sign - --entitlements "$root/ios/Native/HostJIT.entitlements" "$out/core-macos/HostGraphicsChecks"
python3 - "$out/core-macos/HostGraphicsChecks" "$mac_molten/MoltenVK.framework/MoltenVK" "$out/core-graphics" "$out/homebrew/deko_basic.nro" <<'PY'
from pathlib import Path
import subprocess, sys
try:
    subprocess.run(sys.argv[1:], check=True, timeout=90)
finally:
    trace = Path(sys.argv[3]) / "guest-last-run.log"
    if trace.exists():
        print(trace.read_text(), flush=True)
PY

dotnet publish "$root/ios/Runtime/RyuCore.csproj" \
    -c Release -r ios-arm64 -o "$out/core-ios" \
    -p:PublishAot=true -p:PublishAotUsingRuntimePack=true \
    -p:SupportedOSPlatformVersion="$deployment_target" \
    --configfile "$out/upstream/nuget.config"
cp "$out/core-ios/RyuCore.dylib" "$core_framework/RyuCore"
install_name_tool -id '@rpath/RyuCore.framework/RyuCore' "$core_framework/RyuCore"
if otool -l "$core_framework/RyuCore" | grep -A2 LC_RPATH | grep -q 'path @executable_path ('; then
    install_name_tool -rpath '@executable_path' '@executable_path/Frameworks' "$core_framework/RyuCore"
fi

dotnet publish "$root/ios/ManagedEmitter/RyujinxEmitter.csproj" \
    -c Release -r ios-arm64 -o "$out/managed" \
    -p:PublishAot=true -p:PublishAotUsingRuntimePack=true \
    -p:SupportedOSPlatformVersion="$deployment_target"

cp "$out/managed/RyujinxEmitter.dylib" "$framework/RyujinxEmitter"
install_name_tool -id '@rpath/RyujinxEmitter.framework/RyujinxEmitter' "$framework/RyujinxEmitter"
if otool -l "$framework/RyujinxEmitter" | grep -A2 LC_RPATH | grep -q 'path @executable_path ('; then
    install_name_tool -rpath '@executable_path' '@executable_path/Frameworks' "$framework/RyujinxEmitter"
fi
python3 "$root/ios/scripts/package_metadata.py" "$root" "$out" "${GITHUB_RUN_NUMBER:-1}"
cp "$out/homebrew/deko_basic.nro" "$app/deko_basic.nro"
cp "$out/homebrew/NOTICE.txt" "$app/ThirdParty/GraphicsHomebrew-NOTICE.txt"
cp "$out/homebrew/toolchain.txt" "$app/ThirdParty/GraphicsHomebrew-toolchain.txt"

target="arm64-apple-ios$deployment_target"
xcrun clang -target "$target" -isysroot "$sdk" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$root/ios/Native" -c "$root/ios/Native/JITBridge.c" -o "$out/native/JITBridge.o"
xcrun clang -target "$target" -isysroot "$sdk" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$root/ios/Native" -c "$root/ios/Native/CoreWorker.c" -o "$out/native/CoreWorker.o"
xcrun clang -target "$target" -isysroot "$sdk" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$molten_root/include" -c "$root/ios/Native/VulkanProbe.c" -o "$out/native/VulkanProbe.o"
xcrun clang -target "$target" -isysroot "$sdk" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$molten_root/include" -c "$root/ios/Native/MetalSurface.c" -o "$out/native/MetalSurface.o"
xcrun clang -target "$target" -isysroot "$sdk" \
    -c "$root/ios/Native/JITProtocol.S" -o "$out/native/JITProtocol.o"
xcrun --sdk iphoneos swiftc -target "$target" -sdk "$sdk" -swift-version 5 -O -parse-as-library \
    -module-name RyuJIT -import-objc-header "$root/ios/Native/JITBridge.h" \
    -F "$app/Frameworks" -framework RyujinxEmitter -framework RyuCore -framework MoltenVK -framework SwiftUI -framework UIKit \
    -framework Foundation -framework CoreFoundation -framework Metal -framework QuartzCore \
    -Xlinker -rpath -Xlinker '@executable_path/Frameworks' \
    "$root/ios/App/RyuJITApp.swift" "$root/ios/App/JITViewModel.swift" "$root/ios/App/ContentView.swift" "$root/ios/App/BackendChecks.swift" "$root/ios/App/GameLibrary.swift" "$root/ios/App/GraphicsCheck.swift" \
    "$out/native/JITBridge.o" "$out/native/CoreWorker.o" "$out/native/JITProtocol.o" "$out/native/VulkanProbe.o" "$out/native/MetalSurface.o" -o "$app/RyuJIT"

# Ad-hoc signatures preserve requested entitlements for the sideloading tool to inspect.
# This IPA is re-signed by AltStore/SideStore with the user's development profile.
codesign --force --sign - "$framework"
codesign --force --sign - "$core_framework"
codesign --force --sign - "$app/Frameworks/MoltenVK.framework"
codesign --force --sign - --entitlements "$root/ios/App/RyuJIT.entitlements" "$app"
codesign --verify --deep --strict "$app"
codesign -d --entitlements :- "$app" 2> "$out/codesign.log" > "$out/entitlements.plist"
python3 "$root/ios/scripts/verify_package.py" "$app" "$out/entitlements.plist"
ditto -c -k --keepParent "$out/Payload" "$out/RyuJIT-iOS27.ipa"
(cd "$out" && shasum -a 256 RyuJIT-iOS27.ipa > RyuJIT-iOS27.ipa.sha256)
echo "Created $out/RyuJIT-iOS27.ipa (requires AltStore/SideStore signing)."
