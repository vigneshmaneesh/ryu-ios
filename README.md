# Ryu iOS

Native iOS 27 CPU prototype based on Ryujinx's LightningJit AArch64 decoder and compiler, with external StikDebug activation.

Version 0.2 translates six embedded guest programs and tests 25 cases covering branches, guest memory, register remapping, managed callbacks and TLS. The original JIT probe passed on an iPhone 16 and M1 11-inch iPad. The new guest suite needs device validation.

This prototype does not load Switch games yet. See [build and test instructions](ios/README.md).

GitHub Actions uses a standard macOS runner in this public repository, runs the translated guest suite under NativeAOT on Apple Silicon, and builds a re-signable IPA for AltStore Classic or SideStore.
