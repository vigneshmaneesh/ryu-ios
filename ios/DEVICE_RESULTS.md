# Recorded device evidence

All physical-device results below were supplied by the user. Automated Apple
Silicon NativeAOT tests run separately in GitHub Actions.

| Build | iPhone 16 | M1 11-inch iPad |
| --- | --- | --- |
| v0.1 | Four arithmetic inputs passed; signing ready; TXM present; StikDebug | Same reported outcome |
| v0.2 | All 25 guest compiler cases passed | All 25 passed; screenshot supplied |
| v0.3 | Five production CPU groups passed twice | Five production CPU groups passed twice |
| v0.4 build 10 | No v0.4 diagnostics supplied yet | CPU passed three runs; virtual RAM and service checks passed; Vulkan instance returned -7 |
| v0.5.1 build 14 | CPU/platform checks reported working; bundled homebrew closes the app | Same reported outcome |
| v0.5.2 build 17 | Bundled homebrew still crashes | Same reported outcome; recovered trace stops at Switch construction |
| v0.5.3 build 20 | Bundled homebrew passes twice, user confirmed | Bundled homebrew passes twice, user confirmed |
| v0.6.0 build 26 | Production renderer display works, user confirmed | Production renderer display passes twice in the same app session; full trace supplied |

## iPad v0.4 diagnostics

- iPadOS **27.2**; reported physical RAM **7,538 MiB**.
- `get-task-allow=1`, TXM present, prepared region **257 MiB**.
- First test: footprint **16 → 293 MiB**, available memory **5,103 → 4,826 MiB**.
- Next tests ended at **295 MiB** and **298 MiB** footprint.
- Later shared snapshot: footprint **296 MiB**, available **4,823 MiB**.
- 25 compiler cases and all five production CPU groups passed on every shown run.
- **4 GiB virtual RAM / sparse page commits passed**.
- Filesystem/account services passed on an existing mounted session.
- GPU result: **`FAIL Vulkan instance: result -7`** (`VK_ERROR_EXTENSION_NOT_PRESENT`).

The JIT setup's observed footprint increase is roughly 277 MiB. The managed code
allocator touches code pages on demand, but the complete debugger preparation and
aliasing procedure does not have negligible physical cost on this device. Game
RAM, texture/shader storage, video and other runtime allocations remain unmeasured.
The small changes across three runs do not by themselves establish a memory leak.

The GPU fix queries advertised instance extensions and requests portability
enumeration only when present. The user subsequently reported the platform checks
working on both devices in v0.5.1, while homebrew crashed on both. A GPU clear and
readback is backend conformance, not proof that Switch graphics render correctly.

## Homebrew crash investigation

The upstream console target unconditionally calls `Console.ForegroundColor` and
`Console.ResetColor` on its logging thread. Both throw `PlatformNotSupportedException`
in the .NET 10.0.14 iOS console implementation. The asynchronous logger catches a
different exception type, so this path can terminate the process. v0.5.2 avoids
those terminal operations on iOS/tvOS, exercises the actual iOS BCL in simulator CI,
and writes a flushed startup/teardown trace for recovery after reopening the app.
The exact device crash has not been confirmed with an Apple crash report yet.

The user confirmed v0.5.2 build 17 still crashes on both devices. Its persisted
trace ends at `Constructing Switch: RAM, kernel, scheduler and service threads`,
before the NRO is loaded. The logger fix does not establish the crash's cause.

Investigation found that the Swift Dispatch worker enters desktop core code that
creates a 256 KiB HID shared-memory value with additional large temporaries.
v0.5.3 supplies an explicit 8 MiB pthread stack and adds per-constructor checkpoints.
CI tests actual kernel construction in the iOS runtime; device success is not
inferred from simulator or Apple Silicon macOS results.

The user subsequently confirmed **“Both pass perfectly”** when asked to run
v0.5.3 build 20 homebrew twice on each device. This is the accepted device baseline
for real NRO loading, heap/SVC execution, guest exit and kernel teardown. It does
not establish emulated graphics, audio, input or commercial game compatibility.

The [iOS 27.2 runtime comparison](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42404667450/job/128499671711)
reproduced a bus error at `HID shared memory / input initialization` with a
536,576-byte reported native stack (requested 512 KiB). With the requested 8 MiB
stack (8,400,896 bytes reported), Switch construction completed. The constructor-only
test then exposed a separate fixture error: it started shutdown before asynchronous
service registration completed. The normal NRO loader already waits for those
registrations in `ProcessLoaderHelper.LoadNsos`. The fixture now uses that same
readiness barrier before teardown; the app's normal homebrew path is unchanged.

The [corrected iOS-runtime regression](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42405407747/job/128501915738)
then passed two construction/service-readiness/teardown cycles on the larger
worker, while retaining the reproducing small-stack control. Its logging check
also passed. The local `HorizonChecks --startup-only` mode passed twice as well.

## Production renderer device evidence

The user confirmed v0.6.0 build 26 works on the iPhone 16 and ran it twice on the
M1 iPad in the same app session. The visible pattern contained the coloured
regions; this validates host renderer output, not guest GPU command execution.

The supplied iPad trace records iOS 27.2.0, an 8,400,896-byte host stack and
`Apple M1 GPU`. Initialization created the Metal surface and production renderer,
all **36,864 RGBA pixels** matched, and **120 frames** were accepted by the swapchain.
Renderer scope exit completed and the journal ended with `RESULT PASS`.

The on-screen performance overlay reported 1280x720 at 1.0x, direct BGRA8Unorm,
Metal memory 55.25 MB, app memory 389.47 MB, available memory 4.98 GB, 120 Hz,
nominal thermal state, Game Mode off and about 51.17 FPS. These are a single
user-reported renderer-test snapshot. The test deliberately sleeps between frames;
its rate is not a game performance result or a renderer throughput benchmark.

## v0.7.0 bundled graphics homebrew: read-only bundle failure

The user's iOS 27.2 screenshot reports `UnauthorizedAccessException` opening
`App.app/deko_basic.nro`, with inner `IOException: Operation not permitted`.
The trace constructs Switch and initializes Vulkan, then fails in
`ProcessLoader.LoadNxo` before executing the NRO. Kernel/GPU teardown completes.
This is a failed device guest-graphics result, not a successful guest frame.

The upstream NRO stream uses `new(path, FileMode.Open)`, whose implicit access is
read/write. v0.7.1 adds a checked overlay selecting `FileAccess.Read` and
`FileShare.Read`; it preserves the stream lifetime needed for lazy RomFS reads.
The existing single guest smoke boot now uses a file with write permissions
removed and confirms a read/write open is denied before booting it. This replaces
the writable-file smoke input, without adding another emulation run.

## v0.7.1 graphics homebrew accepted

On 8 November the user reported **“everything works perfectly”** after the
v0.7.1 build 32 read-only NRO correction. Treat this as device acceptance of the
bundled real CPU/GPU homebrew path and clean completion. No additional device
model, repeat count, frame count, or audio/input evidence was supplied.

## v0.9.0 commercial XCI rejection

The user's M1 iPad log reaches Vulkan initialization and then rejects the
Tomodachi base XCI before process creation. The underlying error is
`Loader TryLoad: Unable to load: ResultFsOutOfRange (2002-3005)`, followed by clean
Horizon/GPU teardown. The earlier `metaLoader is null` line is emitted when the
upstream failure sentinel is constructed; it does not establish NPDM corruption.
The system-file preflight passed, but this does not validate every game key.
No commercial guest frame or playable game result has been demonstrated.

v0.9.1 fixes a reproduced container-reader contract bug: the pinned LibHac
StreamStorage accepts only a full single Stream.Read, while streams may return
short reads before EOF. An authored HFS0/XCI fixture with an unencrypted NCA
header reproduces 2002-3005 under chunked reads. The complete-read wrapper passes
that same fixture, while actual truncation remains rejected. This establishes a
real reader bug, not proof that it was the only cause of this user's rejection.
