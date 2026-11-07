# Build provenance and rollback

## v0.5.2 logging crash fix

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
selects a compatible simulator from the runner inventory. Device confirmation of
this homebrew fix remains pending. If it still closes, reopen and share diagnostics
before another attempt so the prior `horizon-last-run.log` is preserved.

## Current device test

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
