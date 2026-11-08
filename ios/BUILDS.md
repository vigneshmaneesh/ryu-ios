# Build provenance and rollback

## v0.6.0 production renderer candidate

Accepted renderer device build: **v0.6.0 build 26**, source `38e405f58c3abaf0a3ef79778ec3dcf0e4ca0e40`,
on `feature/ios-renderer`. The default branch retains the accepted build 20 baseline.

- [Successful package and Apple NativeAOT checks](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42411383129/job/128520080903).
- Artifact ID: `13589748017`; one-day retention.
- IPA SHA-256: `d135b4287b35c89e18d989f3bcce0b610cf9680d7cc41de15a6c7a2e0b2412dd`.
- ZIP SHA-256: `0f1db3da2a164a9c1058673ad4119073ab386aa1345bc2967e27bb5946cdb717`.

The upstream renderer passed twice on the Apple runner and twice under the actual
iOS 27.2 simulator runtime: 36,864 rendered pixels verified, 120 successful
swapchain frame presentations per run, then teardown. The first iOS loader path
failed under NativeAOT; this candidate binds commands from the signed framework
directly. Kernel/CPU regressions passed before packaging.

The simulator graphics job then failed in its screenshot command because the
selected device has two displays. A CI-only follow-up selects primary display 1;
it does not alter build 26's app/runtime code. The logger printed PASS but its
simctl transport timed out; the follow-up also extends that command's allowance.
Physical-device and composed-screen confirmation are separate acceptance gates.
This is host renderer conformance, not guest GPU command execution or game boot.

The user supplied a successful M1 iPad trace, confirmed two M1 runs in one app
session, and confirmed the iPhone 16 works. See `DEVICE_RESULTS.md` for the exact
rendering results and reported memory/thermal overlay. Device renderer acceptance
is complete for this diagnostic workload; it is not commercial-game acceptance.

## v0.5.3 kernel worker stack investigation

Accepted device baseline: **v0.5.3 build 20**, source `0a6bbba6ed714daf28c0c2b77f8368bb10377996`.
The user confirmed bundled homebrew passes twice on both the iPhone 16 and M1
11-inch iPad. This is kernel/homebrew conformance, not commercial game acceptance.

- [Successful package/NativeAOT job](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42403680502/job/128496764374).
- Artifact ID: `13586940115`; one-day retention.
- IPA SHA-256: `5ecd557e6faa55288fa2f95c39fd095dfd4daf88bcb4ba6d7ec57d0ccc751768`.
- ZIP SHA-256: `e8a635d5384430fdff14cf0d6c9f437c301dbf02890f5fe702d6a82e773ecfa7`.

Moves the homebrew core call onto an explicit 8 MiB pthread stack, adds saved
constructor checkpoints and tests actual kernel construction twice in the iOS
simulator runtime. No guest JIT is used by that simulator regression. Device
homebrew execution remains the acceptance test; this is still a prototype.

The first simulator attempt timed out during cold iOS boot, before executing the
logger or constructor tests. Its 180-second bootstatus limit was increased to
600 seconds; this CI-only change does not alter the packaged runtime sources.

The [retry](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42404667450)
reproduced the small-stack HID bus error and completed construction on the larger
worker. It failed during constructor-only test teardown because that fixture did
not wait for service registrations. The fixture was corrected to use the same
barrier already called by the normal NRO loader in build 20. No additional device
IPA is needed for that diagnostic-only correction.

The [final iOS runtime regression](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42405407747)
passed: the small-stack control reproduced the HID crash, the explicit-stack
worker completed two real kernel/service construction and teardown cycles, and
the actual iOS BCL logging regression passed. Source:
`693332c6ae61ab3b14ea0b807a9708486aaaf69f`. The simulator executes no guest code;
the user's two-device homebrew results provide that separate acceptance evidence.

## v0.5.2 logging fix and recovered crash trace

Device test: **v0.5.2 build 17**, source `9c24d6be2a3127c4ddafca482abfc6000653cd8c`.

- [Successful package/NativeAOT checks](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42402085741).
- Artifact ID: `13585658903`; one-day retention.
- IPA SHA-256: `5a4a9fec188023b5d381a2bcda6e14cb58efed6e7c747c7dc8c1981e31d44970`.
- ZIP SHA-256: `c762158a6695da1e67cedee0a56f853d2308e083b7c8c424c58448d3eced950f`.

This removes unsupported terminal-colour operations on iOS/tvOS and saves a
flushed Horizon startup/teardown trace, restored into diagnostics after reopening.
Two desktop homebrew boots and interrupted-process journal recovery passed. The
package build passed the compiler/CPU checks and two Apple Silicon NativeAOT
Horizon boots. The actual iOS BCL logger check printed PASS in
[run 42401085097](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42401085097)
before that workflow was cancelled during the packaging restart. The package
branch uses identical runtime sources without repeating simulator startup.

The main workflow now runs mobile logging independently of IPA packaging and
selects a compatible simulator from the runner inventory. The [full main-branch workflow](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42402239040) subsequently passed both IPA packaging and the separate iOS-runtime logging job.
The user then confirmed build 17 still crashes on both devices. The recovered
trace stops during Switch construction, before NRO loading. The logger fix alone
was insufficient.

## Earlier v0.5.1 device build

**v0.5.1 build 14**, source `d3782005fcc240488d69f270cdc5d543b84714ac`.

- [Successful GitHub Actions run](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42399086557).
- Artifact: `RyuJIT-iOS27`, ID `13584368150`, one-day retention.
- IPA SHA-256: `c05c9080b7a11da244eef3c666bf15c803306857bfe40cdcaf97d3130c2dc7a7`.
- Artifact ZIP SHA-256: `0e5a7592a2c2885932ae6feb16c674d1808cea9c78be53fc38cb68d89ff9bfb4`.
- Bundled native frameworks: RyuCore, RyujinxEmitter and official MoltenVK 1.4.2.

CI passed compiler/ABI checks, 100 translated guest executions, all production CPU
groups with four seeds, sparse 4 GiB RAM/service/account checks, and **two real
Horizon NRO boots and teardowns** under Apple Silicon NativeAOT. It then compiled
the iOS app and verified ARM64 device binaries, signing and package contents.
Vulkan execution and Horizon operation on physical iOS devices remain device tests.

Install with AltStore Classic or SideStore. Run **Enable JIT and test**, **Test
platform backends**, then **Boot bundled homebrew**, twice on each device. Share
diagnostics for any failure. This build does not launch commercial games.

## Earlier baseline

The user reported v0.3 CPU tests passed twice on both devices:

- Source: `c2bd777689f200484981a9a9c6fe28ebee864b9f`.
- [Build run](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42395234315).
- IPA SHA-256: `bd88a35e732c764148c395c16eadb517bee301f6da64db160081a39f30fc2199`.

v0.4 build 10 passed CPU/RAM/services on the reported iPad but exposed a requested
Vulkan-extension mismatch. v0.5.1 enables portability enumeration only when the
driver advertises it. See `DEVICE_RESULTS.md` for the supplied measurements.

Expired Actions artifacts can be rebuilt from their immutable source commit on a
public development branch. Keep the last working IPA outside the transient Actions
artifact store. AltStore re-signing changes the package; hashes above identify the
original CI download.

## v0.7.0 graphics homebrew candidate

Built from `3efd2129e8e8e07ad5dc61b9673021ee3d7798bd`, run
[42415982300](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42415982300),
version 0.7.0 build 30. The one Apple NativeAOT guest smoke boot presented **178
frames**, observed libnx's applet exit request and completed kernel/GPU teardown.
The iOS ARM64 IPA and entitlement/content verification succeeded. Device guest
rendering is pending; audio/input and commercial game compatibility remain work.

Routine CI skips the extended CPU/kernel/simulator suite. A delivery-only job
adds the bundled homebrew libraries' notices alongside this unchanged IPA; it
performs no further emulator tests. Later builds embed these notices in the app.

IPA SHA-256: `820f2bb3f5bc1d8eb05963398f416bf5bc7bd7bf46d12a7c824999b65087348b`.
The delivery bundle is [artifact 13591917044](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42416577280/artifacts/13591917044),
with ZIP SHA-256 `377c1f03bba0b014a5a3c9123c2d5c3e1020493bb8b35b060b933dc959dd8663`.
The IPA is unchanged from build 30; the bundle includes the homebrew runtime
notices and installation instructions. Device request: one M1 iPad graphics
homebrew launch and clean completion; no repeated CPU/platform/renderer suite.

## v0.7.1 build 32: read-only bundled NRO correction

Source `c9ce137834094f1b7cd191bebe4d26d90f41e6ed`,
[successful run 42426905522](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42426905522).
[IPA artifact 13596375221](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42426905522/artifacts/13596375221)
expires after one day. IPA SHA-256:
`509c97f881eb78aabe314c6d55422f04dc21f930c745611bc7dce508ff2b901f`.
ZIP SHA-256:
`79647a9c2e7108b00ff296c4690ca1a3fe098688d206e047345f18f4499fc763`.

The previous device result failed before guest execution: the NRO stream implicitly
requested read/write access to the sealed app bundle. The checked upstream overlay
now opens it with `FileAccess.Read, FileShare.Read`. The one Apple NativeAOT smoke
boot confirmed a read/write open is denied, then loaded that read-only NRO,
presented **178 frames**, handled applet exit and completed teardown. No extra
emulation run or full regression suite was added. iOS device ARM64/platform,
iPhone/iPad metadata, contents and signing checks passed. The IPA includes the
homebrew runtime notices. Physical-device graphics remain awaiting one retry.

## v0.8 Apple NativeAOT play integration

Source `adc97916edb6d1172baf5b034db5654ab91a8876`, successful run
[42429816352](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42429816352),
version 0.8.0 build 33, [artifact 13597431274](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42429816352/artifacts/13597431274).
One read-only NRO session rendered **211 frames**, received emulated controller
and touchscreen input, collected a target, consumed **9,600 nonzero PCM frames**
through Apple AudioQueue, paused/resumed and exited cleanly. The native iOS IPA
passed architecture/platform/content/entitlement packaging checks. This is CI
integration evidence; physical v0.8 controls, audio and play remain unconfirmed.

## v0.9 development

Connect NSP/XCI base-game and NRO/NSO launch to the same CPU/GPU/audio/input
session. Add private prod.keys/title.keys import, upstream firmware verification
and installation, transaction rollback/recovery, system status and a setup
preflight that preserves JIT readiness when files are missing. Native applet
requests are bridged into the play screen for messages and text entry; profile
selection uses the existing emulated account. Inline text entry bypasses the
desktop Skia overlay through a checked upstream seam. Commercial title boot and
actual encrypted firmware/key installation are awaiting user files on devices.

## v0.9.0 build 34 candidate

Source `b073e7b618b774deacd1c850870d037362915a15`,
[successful run 42433677519](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42433677519),
[artifact 13598905467](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42433677519/artifacts/13598905467).
IPA SHA-256 `21400b8664a860e03b67436c7a91e6102031aa86cb40b712d8cc0ec95997d941`.
ZIP SHA-256 `381f77a718b0e5b0e1bab0d3f610287d92fca31e427b6a97355c362d38d206ff`.

NativeAOT import checks pass: invalid key input preserves the installed file,
interrupted firmware installation restores the accepted set, committed recovery
cleans the backup, and missing game system files produce a setup preflight.
One real guest play session presents **214 frames**, confirms controller and
touchscreen input, collects a target, consumes **9,600 nonzero PCM frames** through
AudioQueue, pauses/resumes and exits. The iOS ARM64/platform/package/signing checks
pass. Device v0.9 play/audio/input and actual firmware/key installation remain
unconfirmed, as does Tomodachi Life boot. The default branch remains the earlier
accepted baseline; this candidate is on feature/ios-renderer.

The user has the base-game XCI in Files and can dump their Switch firmware. They
were asked to prepare prod.keys and firmware locally. Next device action is one
actual XCI boot after system setup, rather than repeating prototype test suites.

Known follow-up: production session logging still inherits upstream's enabled
trace/debug/stub channels. Reduce these before performance characterization;
current CI timings with syscall logging are not a game-performance benchmark.
