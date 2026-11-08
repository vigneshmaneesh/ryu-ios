# MeloNX source review and integration

## Current status: runtime review modifications reverted

A later functional JIT-loop fix changes the StikDebug activation URL and waiting
lifecycle. It explicitly selects `universal.js` on TXM devices, keeps readiness
only after successful native allocation, prevents repeated automatic handoffs,
and cancels dismissed waiting tasks. This does not reapply the ZIP/callback
fixes or replace the original BreakpointJIT/MoltenVK binaries. The original
encoded legacy script remains in the source for non-TXM activation.

At the user's request, the review-related runtime changes were reverted after
build 5 crashed on a Tomodachi Life launch attempt. This does not establish the
cause of the crash. MeloNX's original ZIP extractor, library callback, encoded
JIT script, BreakpointJIT framework, bundled MoltenVK and memory-donation
defaults are restored. The ZIP/callback findings below therefore apply again.
The source review and its findings are retained as a historical record.
The Ryubing merge, iOS build/ABI compatibility fixes, 8 MiB worker stacks and
the requested FoW App ID remain. A later memory fix restores the stock RAM donor
extension, guest RAM allocation flags and capability gates. The package embeds
MeloNX's increased-memory-limit entitlement request and development debugger
access for AltStore re-signing; final device capabilities are not granted by CI.
Native machine code is retained; ad-hoc re-signing changes binary signature bytes.

Source supplied in `MeloNX Source Code/MeloNX`; clean working tree at
`13700519f3abc4e6d7ed8a065b118b2cc59bcd67` (2026-10-11).
The original checkout is kept unchanged. The file hashes are recorded in
`melonx-source-manifest.json` (4,990 files, including 21 native libraries).

Latest official Ryubing HEAD was queried directly over Git on 2026-11-08:
`a61a42681119bf15fe8f3297677ae48bda83e70f`. This matches the existing iOS pin.

## Confirmed findings â€” user alerted immediately

1. **Game-library disclosure through an unauthenticated callback.**
   `src/MeloNX/MeloNX/Common/AppEnvironment.swift`, `handleDeepLink`,
   `gameInfo` case: accepts an arbitrary callback scheme, encodes every
   `GameScheme`, and opens that scheme without confirmation. Fields include
   title names/IDs, developer/version, icons and host bundle ID. It also exits
   the app when JIT is absent. This is a privacy/availability exposure;
   malicious intent has not been established. Disable this callback.
2. **ZIP extraction directory-boundary bypass.**
   `src/Ryujinx.Library/Compression/NativeZip.cs`: plain
   `entryDestPath.StartsWith(destFull)` accepts a sibling with the same prefix,
   e.g. destination `/data/mod` and entry `../mod-other/file`. Replace with a
   proper normalized relative-path check, reject unsafe/link entries and bound
   extraction size/count before using archive import.

## Review observations and limits

- No key/password upload, telemetry endpoint or malicious build command has
  been identified in the source reviewed so far. This is not a clean-bill-of-
  health claim: review and native dependency verification are still in progress.
- The encoded StikDebug script was decoded, not executed. Its SHA-256 is
  `fffd376fcbab381e303ac2034eab246047868301271c119b38c9b44d9f011c35`.
  It implements debugger protocol/register/memory preparation. Its `eval`
  executes script text obtained from the target process; do not treat the
  base64 encoding alone as proof of malware. Prefer the already verified JIT
  path, or a reviewed source build, for this integration.
- Native frameworks/binaries cannot be declared malware-free from source and
  string scanning. Provenance/hash verification or rebuilding is required for
  stronger assurance. No supplied native binary has been executed locally.
- Swift package manifests at their pinned revisions contain ordinary source
  targets and no build plugins: Melo-Controller
  `c049ce88a5635bddcd88e1965c42aa8fc92fe961`; navigation-stack-backport
  `55acfe7693c233ddc7f62f887f0df6ebd779ef01`.
- The supplied README describes GPLv3 while `LICENSE.txt` contains the Ryujinx
  MIT license. Preserve supplied notices and record the inconsistency; do not
  silently replace licensing information.
- The supplied build script sources interactive shell profiles. The new CI
  build should use an explicit toolchain and environment instead.

## Historical integration work (before the requested rollback)

The earlier integration disabled the game-info callback, replaced the ZIP extractor
with a preflighted, bounded extractor, removed the encoded script, and rebuilt
the three JIT protocol entry points from `../MeloIntegration/BreakpointJIT.S`.
The ZIP regression checks cover prefix-sibling escapes, `..`, absolute paths,
backslash traversal, archive symbolic links and ordinary nested extraction.
The chosen destination is trusted; archive-controlled links at or below it are
rejected. This is not intended to defend against a separate concurrent process
changing the destination during extraction.

MoltenVK was replaced with the official checksum-pinned 1.4.2 package already
used by the existing Ryu builds. The supplied SDL3, FFmpeg, SPIRV and teakra
dependencies remain binary inputs; their original hashes are recorded in
`native-dependencies.json`. Their load commands were inspected for unexpected
external library paths. An exact manifest of packaged binaries is generated by
the Mac build. Binary hashes and ordinary load commands do not prove safety.

The reviewed source paths include native URL handlers, Swift networking and
JIT helpers, archive extraction, native exports, MSBuild/Xcode/shell build hooks,
dependency manifests, memory helpers, crash logging, and the engine/fork diff.
No confirmed credential exfiltration, key upload, persistence payload or
malicious build command was identified in this review. This statement is scoped
to the review performed, not a guarantee that the whole dependency chain is
malware-free. No games, firmware or private keys were uploaded for this work.

The native RAM stress benchmark and private memory donation code are reliability
risks rather than evidence of malicious intent. The historical review build
disabled memory donation and omitted the helper. The current build restores
the stock helper and donation defaults as described above. Only the explicit,
reviewed integration build runs in CI; the supplied shell-profile build hook is
disconnected from the app target.

The current build restores the original components listed above and retains
the latest pinned Ryubing merge. Existing Ryu work remains available on
`feature/ios-parity`; no repeated device-test requests are part of this rollback.
