#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/ios/build/logger-simulator"
mkdir -p "$out"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SDKROOT="$sdk" dotnet publish "$root/ios/IosLoggingChecks/IosLoggingChecks.csproj" \
    -c Release -r iossimulator-arm64 -o "$out" \
    -p:SupportedOSPlatformVersion=18.0
install_name_tool -id '@rpath/IosLoggingChecks.dylib' "$out/IosLoggingChecks.dylib"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios18.0-simulator -isysroot "$sdk" \
    -std=c11 -O2 -Wall -Wextra -Werror "$root/ios/Native/IosLoggingChecks.c" \
    "$out/IosLoggingChecks.dylib" -framework Foundation \
    -Wl,-rpath,@executable_path -o "$out/IosLoggingChecks"
codesign --force --sign - "$out/IosLoggingChecks.dylib"
codesign --force --sign - "$out/IosLoggingChecks"
xcrun simctl list runtimes --json > "$out/runtimes.json"
runtime="$(python3 -c 'import json,sys; r=[x for x in json.load(open(sys.argv[1]))["runtimes"] if x.get("isAvailable") and ".iOS-" in x["identifier"] and int(x["version"].split(".")[0])>=18]; assert r,"An available iOS simulator runtime is required for the mobile logging regression"; print(max(r,key=lambda x:tuple(map(int,x["version"].split("."))))["identifier"])' "$out/runtimes.json")"
device="$(xcrun simctl create RyuLoggingRegression com.apple.CoreSimulator.SimDeviceType.iPhone-16 "$runtime")"
trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1 || true; xcrun simctl delete "$device" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcrun simctl spawn "$device" "$out/IosLoggingChecks"
