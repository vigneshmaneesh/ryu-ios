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
the official .NET mobile library workload, rebuilds the JIT helper from the
included assembly, installs checksum-pinned official MoltenVK, and compiles
MeloNX with Xcode 27. It produces an unsigned IPA for development sideloading.
StikDebug uses `universal.js`, matching the existing tested iOS 27 protocol.

This candidate reuses FoW's bundle ID, `app.fow.explorer`, at the user's request.
The identifier was verified in FoW's project configuration and built IPA.
Signing with the same AltStore account is intended to replace FoW and reuse its
main app ID. The app remains named Ryu MeloNX and does not migrate FoW data.
Keys, firmware and games remain local to the device. The memory donor extension is omitted and
disabled for the free-signing build. Optional entitlement checks no longer
block launch before the actual allocator can report device memory limits.

Existing MeloNX library, accounts, settings, game updates/DLC/mod management,
native input and rendering code are preserved. This does not establish complete
desktop feature parity or compatibility with any commercial title. Build checks
and the security review are separate from device and gameplay validation.

Security findings, mitigations, binary provenance limits and the inconsistent
supplied license notices are documented in `../SecurityReview/MELO-NX-REVIEW.md`.
All original notices are retained. The IPA contains source provenance and a
SHA-256 manifest of the native binaries actually packaged.
