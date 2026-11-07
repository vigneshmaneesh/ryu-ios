#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
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
if [[ "${sdk_version%%.*}" -lt 27 ]]; then
    echo "Select Xcode 27 or newer; the selected iOS SDK is $sdk_version."
    exit 1
fi
mkdir -p "$framework" "$out/native" "$out/managed"

dotnet run --project "$root/ios/EmitterChecks/EmitterChecks.csproj" -c Release
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

target="arm64-apple-ios$deployment_target"
xcrun clang -target "$target" -isysroot "$sdk" -std=c11 -O2 -Wall -Wextra -Werror \
    -I "$root/ios/Native" -c "$root/ios/Native/JITBridge.c" -o "$out/native/JITBridge.o"
xcrun clang -target "$target" -isysroot "$sdk" \
    -c "$root/ios/Native/JITProtocol.S" -o "$out/native/JITProtocol.o"
xcrun swiftc -target "$target" -sdk "$sdk" -swift-version 5 -O -parse-as-library \
    -module-name RyuJIT -import-objc-header "$root/ios/Native/JITBridge.h" \
    -F "$app/Frameworks" -framework RyujinxEmitter -framework SwiftUI -framework UIKit \
    -framework Foundation -framework CoreFoundation \
    -Xlinker -rpath -Xlinker '@executable_path/Frameworks' \
    "$root/ios/App/RyuJITApp.swift" "$root/ios/App/JITViewModel.swift" "$root/ios/App/ContentView.swift" \
    "$out/native/JITBridge.o" "$out/native/JITProtocol.o" -o "$app/RyuJIT"

# Ad-hoc signatures preserve requested entitlements for the sideloading tool to inspect.
# This IPA is re-signed by AltStore/SideStore with the user's development profile.
codesign --force --sign - "$framework"
codesign --force --sign - --entitlements "$root/ios/App/RyuJIT.entitlements" "$app"
codesign --verify --deep --strict "$app"
codesign -d --entitlements :- "$app" 2> "$out/codesign.log" > "$out/entitlements.plist"
python3 "$root/ios/scripts/verify_package.py" "$app" "$out/entitlements.plist"
ditto -c -k --keepParent "$out/Payload" "$out/RyuJIT-iOS27.ipa"
(cd "$out" && shasum -a 256 RyuJIT-iOS27.ipa > RyuJIT-iOS27.ipa.sha256)
echo "Created $out/RyuJIT-iOS27.ipa (requires AltStore/SideStore signing)."
