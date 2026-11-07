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
