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
# Exercise the full constructor under the iOS runtime, without JIT or a game.
SDKROOT="$sdk" dotnet publish "$root/ios/Runtime/RyuCore.csproj" \
    -c Release -r iossimulator-arm64 -o "$out/core" \
    -p:PublishAot=true -p:PublishAotUsingRuntimePack=true \
    -p:SupportedOSPlatformVersion=18.0 --configfile "$root/ios/build/upstream/nuget.config"
install_name_tool -id '@rpath/core/RyuCore.dylib' "$out/core/RyuCore.dylib"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios18.0-simulator -isysroot "$sdk" \
    -std=c11 -O2 -Wall -Wextra -Werror -I "$root/ios/Native" \
    "$root/ios/Native/IosStartupChecks.c" "$root/ios/Native/CoreWorker.c" \
    "$out/core/RyuCore.dylib" -framework Foundation \
    -Wl,-rpath,@executable_path -o "$out/IosStartupChecks"
codesign --force --sign - "$out/core/RyuCore.dylib"
codesign --force --sign - "$out/IosStartupChecks"
echo "Selecting an available, compatible iOS simulator"
python3 -c 'import subprocess,sys; subprocess.run(["xcrun","simctl","list","--json"],stdout=open(sys.argv[1],"w"),check=True,timeout=180)' "$out/inventory.json"
selection="$(python3 "$root/ios/scripts/select_simulator.py" "$out/inventory.json")"
IFS=$'\t' read -r runtime device_type <<< "$selection"
echo "Creating simulator: $device_type / $runtime"
device="$(python3 -c 'import subprocess,sys; print(subprocess.check_output(["xcrun","simctl","create","RyuLoggingRegression",sys.argv[1],sys.argv[2]],text=True,timeout=180).strip())' "$device_type" "$runtime")"
trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1 || true; xcrun simctl delete "$device" >/dev/null 2>&1 || true' EXIT
echo "Booting simulator $device"
python3 -c 'import subprocess,sys; subprocess.run(["xcrun","simctl","boot",sys.argv[1]],check=True,timeout=420)' "$device"
python3 -c 'import subprocess,sys; subprocess.run(["xcrun","simctl","bootstatus",sys.argv[1],"-b"],check=True,timeout=600)' "$device"
python3 -c 'import subprocess,sys; subprocess.run(["xcrun","simctl","spawn",sys.argv[1],sys.argv[2]],check=True,timeout=90)' "$device" "$out/IosLoggingChecks"
# Negative/control case uses a Dispatch-sized stack. A process abort is retained
# as diagnostic evidence; the 8 MiB worker used by the app MUST pass twice.
python3 "$root/ios/scripts/check_startup_process.py" "$device" "$out"
