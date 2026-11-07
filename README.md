# Ryu iOS

Native iOS 27 port of Ryubing, currently a CPU, platform and Horizon homebrew prototype. **Commercial games cannot be launched yet.** The first compatibility target is Tomodachi Life: Living the Dream.

The app runs upstream ARM64 translation and production dispatcher/cache/memory checks through StikDebug on non-jailbroken devices. It also tests LibHac services, virtual RAM reservation, MoltenVK GPU readback and an authored NRO through the real Horizon kernel. The NRO requests a heap, emits a marker and exits; it does not render graphics.

**Current working baseline: v0.5.3 build 20.** The user confirmed bundled homebrew passes twice on both the iPhone 16 and M1 11-inch iPad; CPU and platform backends were previously reported working. The startup crash was reproduced under the iOS runtime on a small thread stack and resolved with an explicit-stack kernel worker. CI now checks two kernel/service startup and teardown cycles on that worker. The next major milestone is an emulated frame presented on the iOS screen.

- [Build and device test instructions](ios/README.md)
- [Numbered milestones and current status](ios/MILESTONES.md)
- [Recorded device evidence](ios/DEVICE_RESULTS.md)
- [Pinned upstream update process](ios/UPSTREAM.md)
- [Port boundaries and remaining work](ios/PORTING_NOTES.md)
- [GitHub Actions builds](https://github.com/vigneshmaneesh/ryu-ios/actions)

Builds use a standard public GitHub runner and produce an ad-hoc signed IPA for re-signing with AltStore Classic or SideStore. StikDebug remains an external JIT enabler. No Apple certificate, paid runner or signing secret is used in CI. Artifacts expire after one day; storage quotas still apply.

The full upstream revision is locked in `ios/upstream.lock.json`. Checked overlays are generated into the build directory; the supplied desktop source remains unchanged. Read the MIT [license](LICENSE.txt) and packaged third-party notices.
