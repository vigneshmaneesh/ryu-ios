# Ryu iOS / Ryu MeloNX — project context and handoff

Last updated: **2026-11-18, Europe/London**.

This is the main continuation document requested by the project owner. Read it
before changing this project. It records the available conversation history,
decisions, source layout, accepted device results, build process and limitations.
It is a practical handoff, not a verbatim transcript. Where old conversation
details are unavailable, this file does not invent them.

## Start here

- Workspace: `D:\Users\vigne\Documents\Project\ryu iOS`.
- The owner wants a native iOS/iPadOS 27 Switch emulator to **play games**.
- Their priority title is **Tomodachi Life: Living the Dream**. Earlier messages
  contain typos such as Tomo life, Tamagotchi Life and agming.
- Devices: **iPhone 16** and **M1 11-inch iPad**, approximately 8 GiB RAM.
- They use **AltStore Classic + StikDebug + LocalDevVPN**, without a jailbreak.
  Their existing Dolphin iOS JIT setup works. Do not explain that JIT is impossible.
- The owner wants free public GitHub CI, and the **finished IPA saved locally**.
- Repository: <https://github.com/vigneshmaneesh/ryu-ios>.
- Active integration branch: `feature/melonx-ryubing`. Do not overwrite main.
- This workspace root is not the integration Git checkout. Remote commits have
  been made through the connected **GitHub plugin**, at the owner's request.
- The generated merged source is `ios/build/melonx`; its reproducible inputs
  are `ios/MeloIntegration/prepare.py`, `resolutions.json` and `overlay/`.
- The supplied original checkout at `MeloNX Source Code/MeloNX` is preserved.
  Do not directly modify it or use generated-source-only edits as final changes.
- Current delivered baseline at the start of this work: **integration build 17**.
  Do not confuse integration build numbers with the older v0.x prototype numbers.
- The owner confirmed playable gameplay on the restored MeloNX configuration
  and a later update installing flawlessly. Do not use the obsolete prototype
  README to claim this is still only an arithmetic test.
- This does **not** establish feature parity with desktop Ryubing or every
  game's compatibility. Most engine code is merged, but the frontend and many
  iOS-specific limitations remain different.
- Do not ask for keys, firmware or games to be uploaded or committed. The owner
  imports their own files on their devices.
- Avoid repeatedly asking for the same tests on both devices. The owner asked
  for fewer tests and more progress. Prefer CI/local checks and one focused
  device attempt when the actual hardware is necessary.

## Current work: November 18

The owner requested all of the following:

1. Save pictures into iOS Photos from the emulator and from the emulated game.
   They report that the current save-to-iOS action crashes the whole app.
2. Update MetalFX to the latest suitable upscaler path in Settings.
3. Label MetalFX/FSR scales with Ultra Performance, Performance, Balanced,
   Quality, Ultra Quality and Native Res, alongside their numeric ratios.
4. On clarification, explicitly chose **only to label existing scale values**,
   rather than secretly lowering game render resolution for Performance mode.
5. Show the **actually used upscaler and implementation version** in the built-in
   in-game performance overlay, including fallback cases.
6. Check whether FSR has a compatible update and update it; it must work on ARM
   and the owner's Apple devices.
7. Create this Markdown context file so future conversations need no full recap.

Work in progress, until the delivery receipt below is updated:

- A Photos exporter with add-only authorization and error handling.
- An in-game Save Screenshot to Photos menu action.
- Guest screenshot/album capture integration that avoids desktop-only Skia
  image encoding on iOS and keeps the guest album JPEG.
- A local picture copy before Photos access is requested; denied permission
  should not discard the capture or terminate the app.
- A Metal 4 spatial backend, GPU event synchronization and resource residency,
  retaining a compatible MetalFX spatial fallback.
- Updated colour-only FSR1 GPU shaders from AMD FSR SDK 2.4.0, retaining an ARM
  GPU path through Vulkan/MoltenVK.
- Runtime upscaler telemetry in the existing FPS/RAM overlay.
- An in-game Performance Overlay switch, so the owner can reveal the upscaler
  status without exiting the game to change settings.
- Global and per-game quality-ratio labels that preserve current configuration.
- Image encoding, channel-order, flip and Metal 4 checks in CI.

Do not call these shipped or device-tested just because this list exists.
The final section records the actual last delivered build and remaining checks.

## Owner preferences and scope decisions

- They want actual changes and a usable IPA, not plans that stop before work.
- Use the GitHub plugin for GitHub when it provides the necessary functions.
- Save the output IPA in the project rather than making them download artifacts.
- Keep saves, keys, firmware, profiles, imports and settings on update.
- **Never tell them to uninstall the working app as a routine update step.**
- Use plain language to explain failures. They are not an emulator developer.
- They previously asked to confirm before adding more menu features. Later
  explicit requests authorized menu visibility changes, Docked Mode and now
  screenshots. This does not authorize arbitrary redesigns or other features.
- They use a physical controller most often. Accommodate touch controls too.
- The menu must be small and unobtrusive, icon only, never controller-centred.
- Previous security-check runtime modifications were reverted at their request.
  Do not silently reapply unrelated security hardening.
- The November performance review was reconnaissance only. It did not authorize
  implementing the entire optimization list. Current requests are targeted
  Photos/upscaler/telemetry work.
- Do not create a goal tool goal unless the owner explicitly requests one.
- Do not spawn subagents unless the owner or applicable project instructions
  explicitly asks for delegation or parallel agent work.

## App identity, installation and local artifacts

The base IDs embedded in the IPA must remain:

- Main: `com.stossy11.MeloNX`.
- Memory extension: `com.stossy11.MeloNX.RamDonor`.

AltStore adds the owner's signing-team component. A screenshot showed:

- `com.stossy11.MeloNX.359SMM7DAQ`.
- `com.stossy11.MeloNX.359SMM7DAQ.RamDonor`.

Do **not** hardcode `359SMM7DAQ` in the input IPA. AltStore can append it again.
Use the same Apple ID as the existing installation, keep bundle ID
randomization disabled, and preserve the memory extension when sideloading.
The extension is an embedded helper, not another app the owner launches.
An update signed to the same installed identity retains the app's data.

Earlier FoW-identity builds through integration build 10 used
`app.fow.explorer`, because the owner asked to reuse the FoW project's ID.
After they supplied their working MeloNX IDs, build 11 onward returned to
stock MeloNX base IDs. Do not switch back to FoW without a new instruction.
Some old filenames still contain FoW; those are historical artifacts.

Primary installer location:

`ios/build/delivery/Ryu-MeloNX-iOS27.ipa`

Other delivery files:

- `Ryu-MeloNX-iOS27.ipa.sha256`.
- `memory-package-verification.json`.
- `integration-provenance.json`.
- `previous-builds/Ryu-MeloNX-iOS27-build<N>.ipa`.

Installer backups are **not backups of phone saves or other phone data**.
The generic filename is replaced only after verifying a new candidate.

Delivered build 17:

- Engine/source commit: `2138ace0e79c68ef15d530ec7d0849fd03282e2f`.
- CI: <https://github.com/vigneshmaneesh/ryu-ios/actions/runs/43592526255>.
- CI job: `132440104257`.
- Artifact: `14112549884`, name `Ryu-MeloNX-iOS27`.
- IPA bytes: `49,283,285`.
- SHA-256: `ab0792e7f409805427f1e686a30667eacf3acaeed521fa8891b175f7f0e624d5`.
- Both base IDs, embedded entitlement requests, 14 native dependencies and stock
  BreakpointJIT/MoltenVK machine code were verified.
- Device validation of the new live dock switch was still outstanding at
  delivery; the owner has not supplied that result in the available history.

Previous build 14:

- Commit: `d498f70322877ed9cf1353629944b7215ebccd75`.
- Tree: `84e8663f813d5613f7e01d3245f7c4f3f9215a16`.
- CI: <https://github.com/vigneshmaneesh/ryu-ios/actions/runs/43101585729>.
- IPA bytes: `49,270,826`.
- SHA-256: `47467e6d87cc5ef5adec4526d5e5eb2994293653fab639c2a898817459cba88e`.
- Its installer was preserved when build 17 was downloaded.

CI artifacts have short retention, generally one day. Historical links may
expire. The local verified IPA is the durable deliverable.

## Source ancestry and maintenance model

Immutable inputs in `ios/MeloIntegration/prepare.py`:

- MeloNX: `13700519f3abc4e6d7ed8a065b118b2cc59bcd67`.
- Ryubing: `a61a42681119bf15fe8f3297677ae48bda83e70f`.
- Common ancestor: `69c22a744e14b2dcc5e2e1ee6f85d305a56a9403`.
- Original merged tree: `a0562a422257f76647aad08f2a5d0f03374339e1`.

Those were the latest official Ryubing sources **verified on November 8**.
Do not call them the current latest on a later date without checking.

The approach is a three-way merge of the related upstream histories, conflict
resolutions checked against both original sides, a small iOS overlay, and
specific integration patches. It keeps iOS code distinct from the bulk engine
so updates are more manageable. It is not guaranteed hot-swapping or plug and
play: updating a source pin still requires reviewing API changes, conflicts,
building and checking relevant behavior.

Files and directories:

| Path | Purpose |
| --- | --- |
| `MeloNX Source Code/MeloNX` | Supplied original checkout; leave clean |
| Root `src/` | Original desktop source; not the active generated iOS tree |
| `ios/build/melonx-merge.git` | Cached bare source repository |
| `ios/build/melonx` | Regenerated merged source |
| `ios/MeloIntegration/prepare.py` | Deterministic merge, overlays and source patches |
| `ios/MeloIntegration/resolutions.json` | Conflict sides and reviewed resolutions |
| `ios/MeloIntegration/overlay/` | Committed replacement/additional source files |
| `ios/MeloIntegration/build.sh` | NativeAOT, Xcode, signing, verification and packaging |
| `ios/MeloIntegration/sign_app.py` | Ad-hoc signatures and entitlement requests |
| `ios/MeloIntegration/verify_ipa.py` | Dependencies, native manifest and package validation |
| `.github/workflows/melonx-ios.yml` | Active public GitHub Actions build |
| `ios/MeloIntegration/JITFlowChecks.swift` | JIT activation lifecycle checks |
| `ios/MeloIntegration/MemoryChecks/` | CPU translation-table and guest-RAM regressions |
| `ios/build/deliver-melonx-memory.py` | Download, verify, archive previous IPA and deliver locally |
| `ios/SecurityReview/MELO-NX-REVIEW.md` | Security findings and rollback history |
| `ios/PerformanceReview/BUILD14-RECON-2026-11-11.md` | Detailed static performance review |
| `ios/MILESTONES.md`, `ios/DEVICE_RESULTS.md` | Historical prototype milestones/results |

The latter prototype documents contain statements like “not playable yet”
that predate the MeloNX pivot. They must not override later accepted gameplay.

## Build and signing process

The owner does not want to pay. The workflow is restricted to public repos and
uses the existing standard `xcode-27` runner. Do not select a paid larger runner
or change account billing/settings. Avoid broad claims about future GitHub
pricing; check current official terms if asked.

Workflow steps:

1. Checkout the integration branch.
2. Select `/Applications/Xcode_27.0.app/Contents/Developer`.
3. Install .NET SDK `10.0.403`.
4. Restore the NuGet/source cache.
5. Run `python3 ios/MeloIntegration/prepare.py`.
6. Run JIT flow and CPU/memory checks.
7. Run any targeted new feature checks.
8. Run `bash ios/MeloIntegration/build.sh`.
9. Upload IPA, checksum, provenance and notices; upload logs on failures.

The engine is published using .NET mobile-librarybuilder:

- Release, `ios-arm64`, shared NativeAOT library.
- iOS deployment target 27.
- `IlcOptimizationPreference=Speed`.
- Single build node and disabled parallel/shared compilation.

The Swift app is built with Xcode Release. Build 14 compiler evidence confirmed
`-O -whole-module-optimization`, not Debug `-Onone`.
GPU threading is explicitly forced on at launch in `RyujinxController.swift`.
Do not propose “turn on Release/GPU threading” as a missing optimization.

The Xcode legacy shell phase that sourced a user profile was disabled by the
integration. The build signs nested code, the memory extension and main app
ad hoc. This needs no Apple development certificate in CI. AltStore then
provisions and re-signs it for the device.

Embedded main entitlement requests:

- `com.apple.developer.kernel.increased-memory-limit = true`.
- `get-task-allow = true`.

The stock memory helper has its original extension identity/principal class.
The app checks what the final installation actually received. An ad-hoc request
does not grant memory permissions by itself. Do not add invented entitlements
or bypass capability checks to mask an allocation failure.

Native dependencies include original supplied BreakpointJIT and MoltenVK.
The manifest hashes packaged signed nested binaries. The main binary is covered
by the outer IPA hash to avoid a self-hash/signature cycle. Verifying the supplied
binary identity does not prove every third-party binary was audited or rebuilt.

For an offline local source regeneration:

```powershell
python ios/MeloIntegration/prepare.py --offline
```

It deletes and recreates **only** the generated `ios/build/melonx` directory
after checking its resolved parent path. Do not run it while another process
uses that tree. A context-mismatch error must be fixed in the patch, not ignored.
On Windows, native iOS compilation needs the Mac CI; a managed build can still
check C# source. The project has local NuGet cache `ios/build/nuget` and
`DOTNET_CLI_HOME=.dotnet-home` for such checks.

## GitHub plugin workflow

Discover current tools; their availability and schemas can change. Previously:

1. Fetch `/git/ref/heads/feature/melonx-ryubing`.
2. Fetch `/git/commits/<head>` for its tree SHA.
3. Read the intended local source files as UTF-8, build tree elements with
   `path`, `mode=100644`, `type=blob`, `content`.
4. Create a tree using the existing tree as base.
5. Create a commit with the observed head as parent.
6. Update the branch with `expected_sha` and `force=false`.
7. Fetch Actions runs filtered by `head_sha`; the commit-workflow wrapper may
   filter PR runs and miss a push workflow.
8. Monitor the specific job and fetch logs only as needed.
9. Fetch/download the successful artifact using plugin tools.
10. Pass its signed download URL privately to the delivery script through stdin.
    Never print the URL or its credentials/tokens.
11. Verify the delivered IPA and retain the previous build.

The downloader validates ZIP and IPA checksums, expected build number, stock
bundle IDs, embedded entitlements, helper metadata, the native manifest and
original JIT/MoltenVK machine-code sections. Local network downloads may need
the execution tool's approved network escalation; this is not a reason to ask
the owner to download manually when the authorized tool can finish it.

Do not print full compiler logs, vendored headers, binary/base64 content,
credentials or giant upload JSON. Avoid Windows command-line length limits
when transferring large files; use a file patch or chunked file operations.

## History: initial prototype

The first objective was native iOS 27 support for Ryubing with JIT on stock
devices. The owner created `vigneshmaneesh/ryu-ios` after the GitHub plugin
could not create a repository. They explicitly asked the agent to build it
through the plugin.

The initial proof progressed through:

- Development signing and executable-memory probes.
- TXM presence and StikDebug JIT activation.
- Arithmetic probe, 25 translated guest instruction cases:
  ADD/overflow 4; branches/loop 5; guest memory 4; reserved registers 4;
  managed SVC callback 4; guest TLS 4.
- Five production CPU groups: dispatcher/BL/RET/SVC, translation invalidation,
  software page tables/remap/tracking, cooperative interrupt/stop, and two
  guest threads/TLS isolation.
- 4 GiB virtual RAM/sparse commitments and account/filesystem services.
- Vulkan/MoltenVK/Metal readbacks, host renderer and then guest graphics.

The owner reported the CPU/JIT groups passed twice on both devices. A v0.4
M1 trace reported approximately 7,538 MiB physical RAM, a 257 MiB prepared code
region, TXM and get-task-allow, and all CPU groups passing; platform graphics
failed Vulkan instance creation with result -7, an unavailable extension.

Prototype homebrew crashes on both devices were narrowed by persistent traces
to Switch/kernel/HID construction. A small worker stack was reproduced in the
iOS simulator. The fix used an explicit approximately 8 MiB native worker
stack; upstream HID initialization returns a large structure by value.

- v0.5.1 build 14: CPU/platform checks worked; bundled homebrew crashed.
- v0.5.2 build 17: still crashed while constructing Switch; added traces.
- v0.5.3 build 20: owner confirmed bundled homebrew passed twice on both.
  Historical run: `42403680502`; later constructor CI `42405407747`.
- v0.6.0 build 26: real production VulkanRenderer to Metal surface; 36,864
  RGBA pixels and 120 presentations with red, green, blue and white quadrants.
  Owner confirmed repeated M1 runs and iPhone 16 success.
  Historical run `42411383129`.

The host quadrant check did not execute guest GPU commands. The subsequent
triangle homebrew did. Its first failure was UnauthorizedAccessException
opening bundled `deko_basic.nro` with writable access in the read-only app
bundle. The loader's read-only stream handling was corrected.

The owner then asked for much larger progress toward playing games and
development through phase 22, with fewer repeated preliminary tests.
They selected Tomodachi Life: Living the Dream as the compatibility target.
Their base game is an XCI in the Files app; they can dump firmware from their
own Switch and import their own keys.

Prototype v0.9 build 34 imported files but title loading failed:

- `metaLoader is null !!!`.
- `Unable to load: ResultFsOutOfRange (2002-3005)`.
- A wrapper InvalidOperationException that the title could not start.

This narrowed the issue to title loading rather than the already passing
CPU arithmetic tests. Do not diagnose missing keys from the wrapper alone.
The earlier read-only game stream/short-read fixes must be preserved.

The owner requested feature-complete testing rather than endless probes, then
supplied MeloNX source and asked for a latest-Ryubing merge and IPA. This was
the major pivot to the current app. Exact old milestone numbering is not a
reliable current feature-completion claim.

## History: MeloNX integration and critical fixes

### Security review and rollback

The owner asked for malicious-code inspection and immediate warning if found.
No confirmed malicious code was established in the available review.
Findings and provenance limits are in `ios/SecurityReview/MELO-NX-REVIEW.md`.
Potential archive/callback concerns were not proof of malicious intent.

After game crashes, the owner explicitly requested undoing the code changes
made as part of security checking. Those runtime changes were rolled back.
The original ZIP extractor, callbacks, JIT framework/scripts, MoltenVK binary,
memory defaults and notices were restored. Subsequent targeted fixes are
functional fixes, not a reapplication of that security-hardening package.

### Repeating StikDebug loop

The owner opened a game, enabled JIT in StikDebug, returned to MeloNX, and got
sent straight back to StikDebug repeatedly. The integration now:

- Uses the current process/PID and `universal.js` for the TXM path.
- Allows only one automatic handoff per activation attempt.
- Uses explicit retry after cancellation or preparation failure.
- Cancels abandoned readiness polling and keeps process-local prepared state.
- Does not assume returning from StikDebug means JIT memory is ready.

Original BreakpointJIT machine code remains intact. Do not revert this fix.

### Cannot allocate memory and sparse tables

The owner supplied logs on November 8, mainly from the **iPhone 16 since the
FoW builds**. An early trace stopped at:

`[SparseMemoryBlock] Reserving 1048576 MB`

Ryubing had moved address-table selection into both CPU contexts, bypassing
MeloNX's earlier iOS exclusion of a flat sparse table. The integration restored
that restriction in a shared `ArmAddressTableFactory`: both JIT backends use a
multi-level table on iOS instead of reserving a 1 TiB translation table.

Do not confuse the translation table with the guest's 4 GiB RAM. Do not undo
this restriction as a performance shortcut.

Subsequent cannot-allocate-memory failures occurred while reserving guest RAM
and then mapping CPU pages through AddressSpacePartitionAllocator.
The actual allocator matched the stock working source. Packaging differed:
the RAM donor extension was missing and the app's executable did not embed
the memory entitlement requests. Project settings alone had not requested
those capabilities from the sideloader.

Build 9's temporary lazy RAM path got farther but was not the final solution.
Build 10 restored stock memory allocation flags (`None` on iOS), donor helper,
runtime entitlement checks and package signing. The owner then requested
stock MeloNX app IDs and confirmed the resulting configuration worked.

Startup scopes unwind processes, kernel, GPU, RAM and audio on failed loads.
The native alert reports the captured startup error instead of only “code -1”.
App-owned filesystem/services/input survive successive sessions.

Avoid claiming an exact Apple OS kill reason without the device crash report.
The logs identify the failed operation; they are not proof of the final
jetsam/exception mechanism.

### Menu access and placement

The stock menu was not appearing when the owner tapped during gameplay,
forcing them to close the app to exit.

- Build 12 made the existing menu visible above gameplay/touch layers.
  The owner said the update worked flawlessly.
- An always-visible labelled button was too persistent.
- Build 13 revealed it on upper-half touches; ordinary Switch touchscreen
  actions then revealed it too often.
- The owner supplied a drawing: a thin yellow strip across the very top of
  the game rectangle should summon a tiny icon in a corner.
- Build 14 implemented the accepted requested geometry.

Current menu reveal behavior:

- Only a narrow **32-point top-edge region** reveals the host menu icon.
- Icon is **ellipsis**, no word “Menu”.
- Approximately 30-point visible symbol with a **44-point tap target**.
- Button fades after **six seconds**.
- Prefer safe upper-right/upper-left corners outside the actual game viewport
  in available black borders; upper-right fallback when no border fits.
- Respect safe areas, Dynamic Island/cutouts and touch-controller placement.
- Do not centre the menu because a physical controller is connected.
- A passive window-level recognizer allows simultaneous gestures and does
  not cancel or delay guest/touch-controller input.
- Menu identity remains mounted while fading to avoid destroying open menus
  or controller sheets. Hidden button ignores taps/accessibility.
- Gesture observer and hide task are removed/cancelled with the gameplay view.
- Settings explain the gesture rather than allowing the only exit control to
  be disabled by an old saved hide-button preference.

Source overlay files:

- `UI/Emulation/EmulationView.swift`.
- `UI/Emulation/GameMenuTapObserver.swift`.
- `UI/Emulation/GameMenuLayout.swift`.
- `UI/Emulation/Config/InGameConfigView.swift`.
- `UI/Emulation/Metal/MetalViewContainer.swift`, `MetalView.swift`.

Existing actions before November 18: Pause/Resume, Docked Mode, Stop Emulation,
Configure Controllers, and iPhone rotation lock.
Restart and a complete desktop-style in-game settings panel are not implemented.

### Build 17: live dock switch and Profile Manager

The owner asked to toggle docked/undocked in the in-game menu, and reported
Profile Manager could not switch/set users or modify active/inactive users.

Docked Mode:

- Native `request_docked_mode(uint8_t)` queues a per-session change.
- The emulation/input thread applies the desktop engine's
  `Horizon.ChangeDockedModeState` before updating guest controllers.
- This changes the guest operation/performance mode and signals display
  resolution and controller notifications.
- Available after the first rendered frame.
- It does not restart the title.
- It is session-only; next launch uses saved global/per-title settings.

Profiles:

- Selection no longer calls a broken close-then-open sequence.
- The old native CloseUser accidentally called OpenUser; corrected.
- EditAccount no longer relies on reading a sheet binding after dismissal
  (the sheet item can already be nil, losing the edit).
- Edits save directly through a native `update_user_profile` entry point.
- Existing user ID and therefore association with saves are preserved.
- Names and avatars of both active and inactive users can be updated.
- AccountManager.Refresh reopens the loaded selected user rather than
  leaving LastOpenedUser pointing at an obsolete profile object.
- Missing/invalid last-user references fall back to a valid user.
- User IDs loaded from JSON are normalized to the engine's canonical form.
- Game auto-selection returns the selected user instead of the arbitrary first
  item from the dictionary.
- iOS profile-file writes use a temporary file and replace the final file.
- If a write fails, edits/selection restore the previous in-memory state.
- The manager has a clear pencil button, selected marker, Done and errors.
- Removing an entry preserves the underlying save files rather than calling
  the engine DeleteUser routine that deletes saves too.

Local lifecycle checks passed: create two users, select one, edit active and
inactive users, refresh, reopen, verify names/avatars/IDs and persisted selection.
Full NativeAOT/Xcode/IPA CI and existing memory/JIT checks passed.

Builds 15 and 16 were intermediate CI attempts. One final patch initially
missed a blank line in the pinned source and failed preparation before compiling.
The corrected complete source generation and build 17 passed.
Do not infer a device failure from those integration-patch failures.

## Performance reconnaissance, completed before feature work

The owner asked for reconnaissance only, explicitly not immediate optimization.
The report is `ios/PerformanceReview/BUILD14-RECON-2026-11-11.md`, with
`build14-source-inventory.json` and `build14-compiler-evidence.json`.
It scanned 4,264 source/shader/project files, about 630,159 lines, and manually
traced active iOS paths. This was static inspection, not every line audited
and not device profiling. All inventoried source hashes and the IPA hash stayed
unchanged during that review.

Main findings and cautions:

1. Input loop waits only 1 ms; player routing can be normalized/allocated
   repeatedly. Cache routing carefully, retain event-driven wakeups and do not
   blindly cap touch/motion/controller updates at 60 Hz.
2. CallbackManager passRetained boxes are overwritten without matching release.
   MemoryUsageMonitor's long-running task may retain its owner; AirPlay and
   battery observers lack explicit lifetime removal. Any fix needs correct
   in-flight native callback ownership, not just releasing objects earlier.
3. HUD statistics arrive at 60 Hz and update multiple published fields. Isolate/
   throttle visible labels while preserving immediate first-frame readiness.
4. Per-title disk shader cache defaults disabled; Vulkan pipeline persistence
   already exists separately. Actual saved user settings were not inspected.
5. Async shader compilation defaults disabled; it can skip incomplete rendering.
   Do not promise free FPS or enable it globally without checking visuals.
6. GC ConserveMemory is set to 9. Confirm the NativeAOT runtime effect and measure
   collections/headroom before relaxing it. iOS memory kills are a real limit.
   Explicit aggressive full collection after Load is teardown, not per-frame.
7. Apple audio uses AVAudioEngine/AVAudioPlayerNode, allocates buffers and converts
   sample layout. Safe pooling needs audio completion and route-change ownership.
8. The old MetalFX path added a Vulkan fence wait, a native command buffer and
   possible Lanczos copy. Removing synchronization blindly is incorrect.
   Output scale alone does not lower internal game resolution.
9. A Vulkan Metal capability check used a macOS-only version test on iOS.
   Validate real feature support before changing it.
10. LightningJit's persistent translation-cache interface is a dummy despite PTC
    options. Adding a real cache is a major ABI/relocation/invalidation project.
    The JIT pool and sparse-table fixes must remain intact.
11. Unified memory budgets and cache reclamation already exist. Blindly doubling
    budgets or disabling reclaims is not established safe optimization.
12. MTKView timed redraw may warrant measuring unused wakeups. It is not proof
    that the game is rendered twice.
13. Sustained thermals, CPU/GPU bottlenecks and title-specific allocations still
    need repeatable game scene measurements.

The build already has Release Swift, speed-oriented NativeAOT and GPU threading.
Reflection.Emit macro JIT cannot simply be enabled in NativeAOT. An old printed
controller-state statement found during the review was commented out, not a
confirmed hot-path logging problem.

No measured FPS gains were claimed. A later optimization request should start
with low-risk input/HUD/lifetime work, then validate cache behavior; do not
implement every speculative recommendation just because this report exists.

## November 18 Photos implementation details

The old game-artwork context menu used
`UIImageWriteToSavedPhotosAlbum(icon, nil, nil, nil)`.
The application had no `NSPhotoLibraryAddUsageDescription` in its Info.plist or
Xcode overrides. Apple requires that description for photo-library writes.
This is a concrete source/package defect consistent with the crash. No current
Apple crash report was supplied to prove that every reported crash has this
single cause.

The guest Caps SaveScreenShot path also used Skia, while the project only
referenced Windows/macOS/Linux native Skia assets. The new iOS route uses native
CoreGraphics/ImageIO JPEG encoding, avoiding this desktop library dependency.

New source/patch architecture:

- `Common/PhotoExporter.swift`: add-only Photos authorization, queue of local
  JPEGs, PHAsset creation, denied/error feedback, link to system Settings,
  short success notice.
- `Common/CaptureImageEncoder.swift`: pure CoreGraphics/ImageIO conversion,
  copied borrowed data, validated dimensions/length, RGBA/BGRA and X/Y flips.
- `Ryujinx.Common/Callbacks/ImageCaptureBridge.cs`: bounded raw pixel ABI.
- Capture request ABI: two pointers, then width, height, byte length, flags,
  result; Swift size 36/stride 40, C# sequential size 40 on ARM64.
- Original native callback data is valid only during the callback. JPEG/local
  file creation completes before returning; no borrowed pointers enter a Task.
- Guest capture writes its original Nintendo/Album JPEG before exporting.
- Emulator screenshots use the production renderer's ScreenCaptured event and
  GPU-thread request path, not a phone UI screenshot with menu/control overlays.
- Menu action: Save Screenshot to Photos.
- Game artwork save uses the same permission-aware exporter.
- Add-only Photos access is sufficient; do not request unnecessary reading of
  the user's entire photo library.
- A local JPEG remains under Documents/screenshots or the guest SD album even
  if Photos access is denied. Local files can be reached through Files.
- The album service should return a failure result on local encoding/write
  failures rather than letting a native boundary exception close the app.

## November 18 upscaler implementation details

MetalFX:

- Apple ships MetalFX in the OS. There is no separate downloadable “MetalFX
  4.1” package version that this project can honestly invent.
- Implement the current **Metal 4 spatial command path** using
  MTL4FXSpatialScaler when runtime support and initialization succeed.
- Retain compatible MTLFXSpatialScaler if unavailable.
- Cross-queue synchronization must cover original MoltenVK work, Metal 4
  upscaling, presentation copy and later frame resource reuse.
- Use GPU events, explicit residency, retained inputs and bounded reusable
  command allocators. Metal 4 command buffers do not retain resources for you.
- New helper: `Metal4SpatialUpscaler.swift`; bridge in `MetalFxBridge.swift`.
- Do not claim newer temporal/denoising features are implemented. They require
  depth, motion vectors, jitter and other frame metadata absent from this
  present-only integration.

FSR:

- Original Vulkan shader was flattened older FSR1 EASU/RCAS code.
- Latest standalone legacy FSR repo still reports v1.0.2, but the current SDK
  contains newer FSR1 GPU code.
- Selected compatible update: AMD FSR SDK **2.4.0**, commit
  `7539ae8b6568ad29ed78a753404351daf3b5cca7`.
- Vendored source:
  `Kits/FidelityFX/upscalers/fsr3/include/gpu/fsr1/ffx_fsr1.h`.
- Local source, adapters, compiler script and attribution:
  `ios/MeloIntegration/Fsr/`.
- Keep its MIT license and embed source attribution in the IPA.
- This is **FSR1 spatial GPU code from SDK 2.4**, not an assertion that FSR4,
  desktop ML DLLs, full SDK host APIs, temporal upscaling or frame generation
  run on this device.
- GLSL adapters use ordinary full-precision GPU arithmetic, preserve renderer
  bindings/dispatch coverage, and compile to Vulkan 1.1 SPIR-V.
- Khronos glslang 16.6.0 downloads are checksum-pinned for Windows and macOS.
- There is no x86 binary or AMD-only wave/ISA requirement in the shipped iOS
  FSR shader. ARM CPU compatibility alone does not guarantee arbitrary AMD
  desktop ML technologies work on Apple's GPU.
- The legacy OpenGL FSR code is not the updated iOS Vulkan shader and must be
  identified honestly if selected.

Labels:

| Name | Output/input ratio |
| --- | --- |
| Native Res | 1.0x |
| Ultra Quality | 1.3x |
| Quality | 1.5x |
| Balanced | 1.7x |
| Performance | 2.0x |
| Ultra Performance | 3.0x |

Do not incorrectly call 2.0x Ultra Performance just to fit a 1x–2x range.
MetalFX keeps its existing numeric/Host values. FSR fits the display; its
sharpness is not a quality scale. Show the ratio guide separately instead of
mislabeling the sharpness percentage. No hidden resScale changes are authorized.

Telemetry:

- Report active renderer behavior, not just saved selection.
- MetalFX display includes Metal 4 versus compatible spatial implementation
  and the current OS version.
- FSR identifies SDK 2.4 / source revision.
- Bilinear fallback or 1.0x bypass should be reported as such.
- `UpscalerTelemetry` is shared by the renderer and host statistics publisher.
- Keep the existing 33-byte statistics ABI intact; a separate status callback
  updates the performance overlay only on change.
- The HUD row belongs to the built-in performance overlay and appears when
  that overlay is enabled. The in-game ellipsis menu provides a Performance
  Overlay toggle; the existing Settings option remains available.

## Useful primary references

- Apple Photos permission:
  <https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryaddusagedescription>
- Apple MetalFX requirements:
  <https://developer.apple.com/documentation/metalfx>
- Metal 4 spatial support check:
  <https://developer.apple.com/documentation/metalfx/mtlfxspatialscalerdescriptor/supportsmetal4fx(_:)>
- Metal 4 spatial protocol:
  <https://developer.apple.com/documentation/metalfx/mtl4fxspatialscaler>
- Metal 4 queue/resource lifetime model:
  <https://developer.apple.com/documentation/metal/understanding-the-metal-4-core-api>
- AMD SDK release:
  <https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/releases/tag/v2.4.0>
- FSR source provenance:
  <https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/7539ae8b6568ad29ed78a753404351daf3b5cca7/Kits/FidelityFX/upscalers/fsr3/include/gpu/fsr1/ffx_fsr1.h>

## Continuation checklist and delivery status

At creation of this handoff:

- Last completed delivery: build 17, at the path and hash above.
- November 18 work is in source and undergoing final preparation/build checks.
- Both new FSR shaders compile locally with pinned glslang.
- New device Photos authorization and Metal 4 behavior have not been observed.
- No new owner crash report is available for the current Photos failure.
- Build status, final commit/run/IPA hash and any test limitations must be
  recorded here when the pending build finishes.

Before making a later change:

1. Check the local delivery receipt and actual GitHub integration branch head.
2. Read any more recent owner instructions; they override historical preferences
   when they explicitly change them.
3. Preserve current bundle IDs, stock memory/JIT behavior and app data.
4. Edit reproducible integration inputs, not only generated sources.
5. Run meaningful checks for the actual change, then deliver the IPA locally.
6. Distinguish source checks, CI success and actual device/user confirmation.
7. Update this file when build state, known bugs or important decisions change.
