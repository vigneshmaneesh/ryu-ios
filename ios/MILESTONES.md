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
| 5 | Pinned upstream and versioned iOS boundary | Implemented: immutable source lock, checked overlays, C ABI v1; Apple CI/device validation underway |
| 6 | Production dispatcher | Integrated for software page tables; local dispatcher/BL/RET/SVC checks pass; Apple validation pending |
| 7 | Production translation cache and invalidation | Integrated with prepared RW/RX aliases; local stale-code regression passes; Apple validation pending |
| 8 | Production guest memory and permissions/tracking | Real software page tables and remapping tested locally; iOS production address space, permission faults and fast tracking incomplete |
| 9 | Threads, interrupts, timers and synchronization | Local cooperative interrupt and concurrent guest TLS checks pass; Horizon scheduling and synchronization incomplete |
| 10 | Horizon kernel and services | Not integrated into the iOS runtime |
| 11 | Real homebrew loading/execution | Not integrated; current embedded programs are CPU conformance tests |
| 12 | iOS Vulkan/MoltenVK graphics and first frame | Not integrated |
| 13 | Shader translation, cache and correctness | Not integrated |
| 14 | Native audio | Not integrated |
| 15 | Controllers, touch and motion | Not integrated |
| 16 | Sandboxed game, firmware, key and update imports | Not integrated |
| 17 | First compatible commercial game boot | Not demonstrated; target above |
| 18 | Game library, settings, saves and per-title configuration | Not integrated |
| 19 | Pause/resume, backgrounding, memory pressure | JIT activation has cancellation/background handling; emulator lifecycle incomplete |
| 20 | Performance, memory, thermals and battery | Not characterized for games |
| 21 | Device regression and upstream compatibility matrix | Prototype regression exists; full emulator matrix incomplete |
| 22 | First usable release, packaging, diagnostics and rollback | Not complete; cannot call the CPU prototype a usable emulator |
| 23 | Repeatable upstream updates | Lock/overlay mechanism implemented; full compatibility validation remains required |
| 24 | Optional DLC, mods and multiplayer | Deferred |

## Next hardware gate

v0.3 must report **Production CPU passed** on both devices and on a second run
without relaunching. It keeps the v0.2 suite and adds five production CPU groups.
The virtual executable pool grows to 256 MiB; device preparation, physical memory
usage and repeated code publication require hardware validation before relying on
this allocator for Horizon and game execution.

Continue phases 8–17 with a small redistributable homebrew workload before using
the commercial target to diagnose multiple unverified subsystems at once.
