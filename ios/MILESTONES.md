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
| 9 | Threads, interrupts, timers and synchronization | Cooperative interrupt and concurrent guest TLS checks pass both devices; Horizon scheduling and synchronization incomplete |
| 10 | Horizon kernel and services | LibHac filesystem/ARP/BCAT/account bootstrap implemented and passes desktop checks; Apple AOT/device validation underway; Switch kernel not integrated |
| 11 | Real homebrew loading/execution | Not integrated; current embedded programs are CPU conformance tests |
| 12 | iOS Vulkan/MoltenVK graphics and first frame | Official iOS MoltenVK pinned; native offscreen GPU clear/readback probe implemented; emulated GPU and presentation not integrated |
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

The user reported **v0.3 passed twice on both devices**, covering all 25 compiler
cases and five production CPU groups with the 256 MiB virtual JIT pool.
v0.3 was built from `c2bd777689f200484981a9a9c6fe28ebee864b9f`, run
[42395234315](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42395234315).

The next device check is v0.4's **Test platform backends**: actual emulated account
persistence and offscreen MoltenVK/Metal clear/readback. This validates backend
operations, not Switch graphics or a commercial game boot.

Continue phases 8–17 with a small redistributable homebrew workload before using
the commercial target to diagnose multiple unverified subsystems at once.
