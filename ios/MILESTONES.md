# Native iOS roadmap

First game target: **Tomodachi Life: Living the Dream**. Its compatibility is
unverified. An embedded CPU test passing is not evidence that a commercial game boots.

Status recorded 7 November 2026. Device results are user reports, not remotely
observed instrumentation. The original milestone numbers remain fixed.

| Phase | Deliverable | Evidence / status |
| --- | --- | --- |
| 1 | Native iPhone/iPad app and NativeAOT bridge | Complete: v0.1 |
| 2 | Public GitHub Actions, re-signable IPA, no paid runner | Complete: v0.1/v0.2 artifacts built |
| 3 | StikDebug JIT with TXM on both devices | Complete: user reports v0.1 success on iPhone 16 and M1 11-inch iPad |
| 4 | Actual upstream guest compiler conformance | Complete: 25 cases; user reports v0.2 success on both devices |
| 5 | Pinned upstream and versioned iOS boundary | Complete for current adapter: immutable source lock, checked overlays, C ABI v1; Apple CI and both devices pass |
| 6 | Production dispatcher | Integrated for software page tables; dispatcher/BL/RET/SVC checks pass Apple NativeAOT and both devices twice |
| 7 | Production translation cache and invalidation | Prepared RW/RX cache and stale-code regression pass Apple NativeAOT and both devices twice |
| 8 | Production guest memory and permissions/tracking | Real software page tables and remapping pass both devices; game-sized address space, permission faults and fast tracking incomplete |
| 9 | Threads, interrupts, timers and synchronization | Interrupt/TLS checks and real Horizon scheduling for the authored NRO pass both devices; broader synchronization coverage incomplete |
| 10 | Horizon kernel and services | Real initialization, service startup and teardown pass twice on both devices in v0.5.3 build 20; commercial service compatibility unverified |
| 11 | Real homebrew loading/execution | Complete for the authored NRO: real SetHeapSize, OutputDebugString and ExitProcess pass twice on desktop, Apple NativeAOT and both devices |
| 12 | iOS Vulkan/MoltenVK graphics and first frame | Upstream VulkanRenderer / Metal surface / swapchain conformance passes both devices in v0.6 build 26; M1 repeat and trace confirmed; v0.7 build 30 presents 178 real guest frames and exits cleanly on Apple NativeAOT; device guest display pending |
| 13 | Shader translation, cache and correctness | Upstream SPIR-V guest shader translation runs in the v0.7 triangle smoke boot; broader shader/cache correctness unverified |
| 14 | Native audio | Not integrated |
| 15 | Controllers, touch and motion | Not integrated |
| 16 | Sandboxed game, firmware, key and update imports | Native game/homebrew importer and signature checks implemented; device validation pending; firmware/keys/updates not integrated |
| 17 | First compatible commercial game boot | Not demonstrated; target above |
| 18 | Game library, settings, saves and per-title configuration | Persistent native imported-title list implemented; settings/saves/per-title configuration not integrated |
| 19 | Pause/resume, backgrounding, memory pressure | JIT activation has cancellation/background handling; emulator lifecycle incomplete |
| 20 | Performance, memory, thermals and battery | Not characterized for games |
| 21 | Device regression and upstream compatibility matrix | Prototype regression exists; full emulator matrix incomplete |
| 22 | First usable release, packaging, diagnostics and rollback | Not complete; cannot call the CPU prototype a usable emulator |
| 23 | Repeatable upstream updates | Lock/overlay mechanism implemented; full compatibility validation remains required |
| 24 | Optional DLC, mods and multiplayer | Deferred |

## Current baseline and next hardware gate

**v0.5.3 build 20 passes bundled homebrew twice on both devices**, confirmed by the
user. This is the accepted kernel/homebrew baseline. Next: phase 12, connecting
the actual emulated GPU renderer to an iOS presentation surface and validating a
visible homebrew frame. The existing offscreen clear/readback does not satisfy it.

The user has now accepted **v0.6.0 build 26's host renderer display on both devices**,
including a repeated M1 iPad run. The real upstream backend verifies 36,864 pixels
and presents 120 frames. This establishes the iOS screen/renderer bridge; phase 12
still requires guest GPU command submission and a homebrew-rendered frame.

The user reported **v0.3 passed twice on both devices**, covering all 25 compiler
cases and five production CPU groups with the 256 MiB virtual JIT pool.
v0.3 was built from `c2bd777689f200484981a9a9c6fe28ebee864b9f`, run
[42395234315](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42395234315).

The iPad v0.4 report passed RAM and service checks but Vulkan instance creation
failed with an unavailable extension; see `DEVICE_RESULTS.md`.

The user reports v0.5.1 CPU/platform checks working but homebrew crashing on both
devices. v0.5.2 removes an unsupported mobile console-colour call path, adds an
actual iOS-runtime logger regression, and persists startup stages across relaunch.
Both devices still crash with v0.5.2 build 17; its trace narrows the failure to
Switch construction. v0.5.3 adds an explicit-stack native worker, detailed
constructor checkpoints and actual iOS-runtime kernel construction checks.
The user confirmed that the new build passes perfectly on both devices when asked
to run homebrew twice. This is real kernel execution, but does not yet test
emulated graphics or a commercial game.
The actual iOS-runtime constructor/readiness/teardown regression also passes
twice in [CI](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42405407747).

Continue phases 8–17 with a small redistributable homebrew workload before using
the commercial target to diagnose multiple unverified subsystems at once.

## v0.7 work in progress

v0.7 build 30 connects real NRO execution to the GPU FIFO, shader translator and
Metal presentation loop, with a bundled public-domain deko3d triangle and launch
buttons for imported NROs. The Apple NativeAOT smoke boot presented 178 guest frames and completed kernel/GPU teardown. Device guest graphics and commercial game compatibility are still unverified.

Routine CI now builds the homebrew and IPA with one actual guest boot. The full
CPU/kernel and simulator regression suite is opt-in using `extended_checks`.
Physical-device validation is requested once per meaningful milestone.
