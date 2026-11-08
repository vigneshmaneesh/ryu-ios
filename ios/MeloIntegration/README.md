# Ryu MeloNX integration

The native MeloNX frontend and iOS platform changes are merged with the latest
official Ryubing commit verified on 2026-11-08. Both inputs are immutable pins
in `prepare.py`; the original supplied checkout remains untouched.

The common ancestor makes updates ordinary three-way merges. Updating a pin
requires reviewing changed conflicts and APIs, rebuilding and checking the
result. It is not guaranteed to be plug-and-play. `resolutions.json` records the
original conflict sides and the reviewed resolution; changed conflict contexts
fail preparation rather than silently choosing a side.

The workflow `.github/workflows/melonx-ios.yml` builds the native engine using
the official .NET mobile library workload and compiles MeloNX with Xcode 27.
It produces an unsigned IPA for development sideloading. At the user's request,
the security-review runtime modifications have been reverted: the original
MeloNX ZIP extractor, library callback, JIT script/framework, bundled MoltenVK
and memory-donation defaults are restored. StikDebug remains the default
provider. A subsequent JIT-loop fix explicitly selects `universal.js` for TXM
devices and the current process. It keeps one automatic handoff per attempt,
offers explicit retry, cancels abandoned waiting tasks and remembers successful
native memory preparation for the current process. JIT readiness is never
inferred merely from returning from StikDebug. The original BreakpointJIT
framework, encoded legacy script and MoltenVK binary remain present.

This candidate reuses FoW's bundle ID, `app.fow.explorer`, at the user's request.
The identifier was verified in FoW's project configuration and built IPA.
Signing with the same AltStore account is intended to replace FoW and reuse its
main app ID. The app remains named Ryu MeloNX and does not migrate FoW data.
Keys, firmware and games remain local to the device. The memory donor extension
is omitted for the free-signing build. Its original defaults are restored; it
cannot donate memory while its helper is absent. Optional entitlement checks no longer
block launch before the actual allocator can report device memory limits.

Existing MeloNX library, accounts, settings, game updates/DLC/mod management,
native input and rendering code are preserved. This does not establish complete
desktop feature parity or compatibility with any commercial title. Build checks
and the security review are separate from device and gameplay validation.

Security findings, the rollback status, binary provenance limits and inconsistent
supplied license notices are documented in `../SecurityReview/MELO-NX-REVIEW.md`.
All original notices are retained. The IPA contains source provenance and a
SHA-256 manifest of the native binaries actually packaged.

`JITFlowChecks.swift` exercises the actual production activation coordinator's
return/retry and readiness transitions on the Mac runner. It does not substitute
for device-side StikDebug or gameplay validation.

The Tomodachi startup logs supplied on 2026-11-08 all ended at
`[SparseMemoryBlock] Reserving 1048576 MB`. Upstream moved CPU table selection
into both CPU contexts, bypassing MeloNX's previous iOS sparse-table exclusion.
The integration restores that exclusion through `ArmAddressTableFactory` for
both engines. iOS now uses the multi-level translation lookup table, allocating
small pages as needed instead of reserving the flat 1 TiB range. Game RAM size,
memory-manager selection and JIT code-cache behavior are unchanged.

`MemoryChecks` tests the production factory for every memory-manager type and
both guest CPU widths, writes/reads translations at distant guest addresses,
and checks dispatcher defaults, isolation and invalidation. The device logs
identify the shared last startup operation; they do not contain Apple's final
termination reason, so this is not proof of the exact OS termination mechanism
or a guarantee that no later game-compatibility issue will appear.

The subsequent iPhone 16 logs reported `Cannot allocate memory` in the Switch
constructor before title loading. The iOS guest-RAM path had requested a 4 GiB
read/write mapping. `GuestRamAllocator` now reserves the same full address range
and relies on the kernel's existing page-commit calls to make used pages
accessible. It logs requested size, mode and allocation flags. Allocation
failure is not proof that the phone physically ran out of RAM; the logs do not
report its current address-space or memory-limit state.

Construction/startup scopes now unwind resources after exceptions and rejected
loads. Teardown stops guest processes and the kernel, releases GPU resources,
then releases guest RAM/audio. App-owned filesystem, service clients and input
survive iOS game sessions. Native UI alerts include the captured startup
exception rather than just `-1`. The memory checks exercise real 4 GiB
reservations, first/middle/last page access, repeated failed-startup releases,
retry and successful ownership transfer. These checks are host regressions;
they do not establish available RAM or successful gameplay on an iPhone.
