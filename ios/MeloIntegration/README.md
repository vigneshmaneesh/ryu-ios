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
It produces an ad-hoc signed IPA for development sideloading; AltStore must
provision and re-sign it for the user's device. At the user's request,
the security-review runtime modifications have been reverted: the original
MeloNX ZIP extractor, library callback, JIT script/framework, bundled MoltenVK
and memory-donation defaults are restored. StikDebug remains the default
provider. A subsequent JIT-loop fix explicitly selects `universal.js` for TXM
devices and the current process. It keeps one automatic handoff per attempt,
offers explicit retry, cancels abandoned waiting tasks and remembers successful
native memory preparation for the current process. JIT readiness is never
inferred merely from returning from StikDebug. The original BreakpointJIT
framework, encoded legacy script and MoltenVK binary remain present.

This candidate uses stock MeloNX's bundle ID, `com.stossy11.MeloNX`, at the
user's request to reuse the existing MeloNX registrations. This replaces the
FoW identity used in builds through 10. AltStore adds the Apple team identifier
to the parent ID and preserves the `.RamDonor` extension suffix, yielding
`com.stossy11.MeloNX.TEAMID` and `com.stossy11.MeloNX.TEAMID.RamDonor`.
The account suffix must not be hard-coded into the input IPA, since AltStore
would append it again for a new registration. Use the same Apple ID as the
existing MeloNX installation and keep bundle-ID randomization disabled to reuse
the existing registrations. Installing this candidate updates MeloNX rather
than FoW. The app remains named Ryu MeloNX.
AltStore's implementation is documented in its
[provisioning operation](https://github.com/altstoreio/AltStore/blob/develop/AltStore/Operations/FetchProvisioningProfilesOperation.swift).
Keys, firmware and games remain local to the device. The stock memory donor
extension is embedded as `com.stossy11.MeloNX.RamDonor`, preserving the original
memory-donation defaults and helper code. It uses an additional extension App ID;
it is not a separately launched app. Keep the extension when sideloading.
The stock memory-capability gates are restored and log the permissions reported
by the running installation. Both missing-capability alerts are displayed.

Existing MeloNX library, accounts, settings, game updates/DLC/mod management,
native input and rendering code are preserved. This does not establish complete
desktop feature parity or compatibility with any commercial title. Build checks
and the security review are separate from device and gameplay validation.

The in-game host menu starts hidden. Only a narrow 32-point strip at the top of
the usable screen reveals its button for six seconds; the rest of the game
touchscreen cannot reveal it. Repeated strip/button taps reset the deadline.
The button stays above the Metal view, virtual controller and loading overlay.
Its visible label is a small 30-point ellipsis symbol, with a transparent
44-point touch target and an accessibility label. It never moves to the centre.
Actual game-image bounds are passed up with a SwiftUI anchor preference. The
layout prefers safe upper-right/upper-left corners outside those bounds; with
no virtual controls, lower black-border corners can also be used. If the game
fills all eligible corners, it uses the safe upper-right corner. Safe-area
insets and margins keep the control away from the Dynamic Island and cutouts.
A temporary window-level UIKit tap
observer detects taps even when virtual controls receive them, permits simultaneous
gestures, and neither cancels nor delays game/controller touches. It is removed
when the gameplay view leaves. Visibility updates and timer cancellation run on
the main actor; the menu view stays mounted while its button fades, preserving
native menu/sheet identity. Hidden buttons cannot receive taps or accessibility
focus. Global/per-game settings explain the top-edge gesture rather than
offering to disable the only exit control. The reveal tap also reaches the game.
The menu includes Pause/Resume, Docked Mode, Stop Emulation, controller
configuration and iPhone rotation lock. Docked Mode becomes available after
the first frame and uses the desktop engine's live mode change, including
guest display and controller notifications. The change lasts for the current
session; the saved game settings determine the next launch mode.

In Profile Manager, tap a profile row to select it and use its pencil button
to edit it. The engine writes the profile changes before the edit sheet
closes and keeps the original user ID. Removing a profile entry leaves its
game save files on the device.

Security findings, the rollback status, binary provenance limits and inconsistent
supplied license notices are documented in `../SecurityReview/MELO-NX-REVIEW.md`.
All original notices are retained. The IPA contains source provenance and a
SHA-256 manifest of the signed nested native binaries actually packaged. The
main executable is covered by the final IPA checksum to avoid a self-hash cycle
when the root signature seals the manifest.

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
constructor before title loading. Build 9's lazy reservation passed that stage;
the 17:25 log then failed in `AddressSpacePartitionAllocator` while mapping the
game's CPU pages. That allocator and its underlying memory code already match
the supplied MeloNX source byte-for-byte. The log also explicitly reports that
the RAM donor extension is absent. Build 9's IPA has no embedded entitlements,
so its `CODE_SIGN_ENTITLEMENTS` project setting alone supplied no memory request
to the sideloader. These are confirmed packaging differences, not proof that
the device ran out of physical RAM or that the helper alone fixes this failure.

The current build restores MeloNX's actual guest RAM allocation flags (`None`
on iOS), RAM helper and runtime capability checks. `sign_app.py` embeds the stock
`increased-memory-limit` request plus `get-task-allow` for StikDebug using ad-hoc
signing, then validates both bundles and their signatures. This needs no Apple
certificate in CI. It does not grant device capabilities: AltStore Classic 2.2+
supports requesting Increased Memory Limit, and the installed app checks what
its final signature reports. No additional virtual-addressing entitlement is
invented or assumed. A new device launch is still needed to establish whether
the restored stock configuration gets past the CPU mapping failure.

Construction/startup scopes now unwind resources after exceptions and rejected
loads. Teardown stops guest processes and the kernel, releases GPU resources,
then releases guest RAM/audio. App-owned filesystem, service clients and input
survive iOS game sessions. Native UI alerts include the captured startup
exception rather than just `-1`. The memory checks exercise real 4 GiB mappings
using the stock flags, first/middle/last page access, repeated failed-startup releases,
retry and successful ownership transfer. These checks are host regressions;
they do not establish available RAM or successful gameplay on an iPhone.
