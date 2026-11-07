# Build provenance and rollback

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
