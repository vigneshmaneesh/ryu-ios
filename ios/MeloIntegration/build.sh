#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
source_root="$root/ios/build/melonx"
deps="$source_root/src/MeloNX/MeloNX/Dependencies"

dotnet workload install mobile-librarybuilder --skip-manifest-update

# Use MeloNX's supplied MoltenVK and BreakpointJIT binaries unchanged.
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
export SDKROOT="$sdk"

dotnet publish "$source_root/src/Ryujinx.Library/Ryujinx.Library.csproj" \
  -c Release -r ios-arm64 -p:NativeLib=Shared -p:NuGetAudit=false \
  -p:SupportedOSPlatformVersion=27.0 -p:GeneratePackageOnBuild=false \
  -p:IlcOptimizationPreference=Speed -m:1 -nodeReuse:false \
  -p:BuildInParallel=false -p:UseSharedCompilation=false \
  2>&1 | tee ios/build/melonx-engine.log

xcodebuild -project "$source_root/src/MeloNX/MeloNX.xcodeproj" \
  -scheme MeloNX -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$root/ios/build/melonx-derived" \
  -clonedSourcePackagesDirPath "$root/ios/build/melonx-packages" \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  build 2>&1 | tee ios/build/melonx-xcode.log

app="$root/ios/build/melonx-derived/Build/Products/Release-iphoneos/MeloNX.app"
test -f "$app/MeloNX"
test -f "$app/Frameworks/Ryujinx.Library.dylib"
mkdir -p "$app/SourceNotices"
cp "$source_root/LICENSE.txt" "$source_root/README.md" "$source_root/integration-provenance.json" "$app/SourceNotices/"
cp "$source_root/distribution/legal/THIRDPARTY.md" "$app/SourceNotices/"
cp ios/SecurityReview/MELO-NX-REVIEW.md "$app/SourceNotices/"
find "$source_root/src/Ryujinx.Library/bin/Release/net10.0/ios-arm64" -name 'icudt*.dat' -exec cp {} "$app/" \;

# Validate Mach-O dependencies and record the exact native binaries shipped.
python3 ios/MeloIntegration/verify_ipa.py "$app"
stage="$root/ios/build/melonx-package"
mkdir -p "$stage/Payload"
ditto "$app" "$stage/Payload/MeloNX.app"
(cd "$stage" && zip -q -r "$root/ios/build/Ryu-MeloNX-iOS27.ipa" Payload)
shasum -a 256 ios/build/Ryu-MeloNX-iOS27.ipa > ios/build/Ryu-MeloNX-iOS27.ipa.sha256
cat ios/build/Ryu-MeloNX-iOS27.ipa.sha256
