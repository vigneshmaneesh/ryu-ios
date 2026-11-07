# Ryu iOS: production CPU integration (v0.3)

This is an iOS 27 **CPU prototype**, not a playable Switch emulator yet.
The first commercial compatibility target is **Tomodachi Life: Living the Dream**;
no game boot or performance claim has been established.

v0.3 adds the complete upstream CPU engine, production dispatcher and translation
cache, real software page tables, interrupts and concurrent guest contexts. Five
new groups test BL/RET/SVC dispatch, modified-code invalidation, guest-page remaps,
cooperative interrupt/stop, and two guest threads with isolated TLS. It prepares a
256 MiB virtual code pool plus a 1 MiB conformance region through StikDebug.
Native code is written through RW aliases and published at stable RX addresses.
Physical pages are touched on demand by the allocator; actual device footprint
and debugger preparation behavior still require measurement.

The core is pinned to a full upstream commit with checked platform overlays and
a versioned C interface. See [the update process](UPSTREAM.md) and the original
[numbered roadmap](MILESTONES.md). The supplied desktop source is unchanged.

The v0.2 regression suite is retained:
It is a native SwiftUI app for iPhone and iPad, with a small NativeAOT C# framework
that compiles the **actual LightningJit AArch64 decoder, compiler, register
allocator and native context from this repository**. After StikDebug activation
it runs the original four-input arithmetic probe, then translates six embedded
guest programs and executes 25 cases:

- 64-bit addition and overflow.
- Conditional branches, flags and a backwards loop.
- Guest loads and stores in a bounded 64 KiB address space, with guard checks.
- Guest X18/X29 remapping and host ABI preservation.
- An SVC callback into managed code, changing registers and resuming the guest.
- Emulated thread-local storage register reads.

The memory adapter implements `IJitMemoryAllocator` over the native coordinator's
prepared region, with a stable RX pointer and an explicit RW alias for writing.
The callback adapter is a conformance harness, not an implementation of Horizon
services. This version does not boot Horizon, render Switch graphics or load games.
Large game address spaces, permission faults, fast memory tracking, Horizon,
graphics, audio and game loading still need integration and hardware validation.

## Build for £0 with GitHub Actions

1. Put this source in a **public** GitHub repository.
2. Open **Actions → iOS 27 JIT proof of concept → Run workflow**.
3. Download the **RyuJIT-iOS27** artifact after the build succeeds; unzip it to
   obtain `RyuJIT-iOS27.ipa`.
4. Install the IPA with **AltStore Classic or SideStore** on each device.

The workflow uses the standard `xcode-27` runner and refuses to build in a private
repository. It uses no Apple certificate, Apple ID, signing secret, paid runner,
or third-party build service. Artifact retention is one day, with no persistent
build cache. Keep total account artifact storage within GitHub Free's allowance;
GitHub Releases can host IPAs for longer-term downloads. Keep paid usage disabled
in your GitHub billing settings. Free standard public-repository compute does not
remove GitHub's separate artifact/cache storage quotas.

The build selects Xcode 27.0 and installs .NET 10.0.301, matching `global.json`.
The NativeAOT framework does not need the .NET iOS workload because the UI is Swift.
CI compiles and checks the package; device-side JIT remains a hardware test.

For a local Mac build with the same SDK, run `bash ios/scripts/build-ios.sh`.
The script produces an ad-hoc signed, **re-signable** IPA, not an IPA that can be
installed directly without AltStore/SideStore signing. The installed development
profile must preserve `get-task-allow`.

## Test on the iPhone 16 and M1 11-inch iPad

1. Use the existing StikDebug pairing setup and connect LocalDevVPN.
2. Open **Ryu JIT** and tap **Enable JIT and test**.
3. Let StikDebug process the request, then return to Ryu JIT if necessary.
4. A successful v0.3 test displays **Production CPU passed**, retaining all
   **25 compiler cases** and adding **5 production CPU groups**. Run it again
   without closing the app to check cache-pool reuse and a new random input seed.
5. Use **Share diagnostics** to copy the OS version, protection/signing status,
   and test stages. Pairing files and Apple credentials are never read by this app.

On TXM devices the app requests StikDebug's fixed `universal.js` script. It waits
for `CS_DEBUGGED`, requests the executable region with the universal breakpoint
protocol, creates a separate RW alias, and detaches the debugger before execution.
On non-TXM devices it uses ordinary external debugger activation and no script.
Unknown TXM status blocks activation instead of guessing. The app does not claim
JIT is ready just because StikDebug opened or a debugger flag appeared: the
generated function must actually execute and pass all four checks.

Activation times out after two minutes. Cancelling stops the debugger-wait stage;
an active breakpoint handshake must finish before the app can report its outcome.
After a preparation error, close the app completely and restart before retrying.
Updating StikDebug may be necessary for its `enable-jit` URL and `universal.js`
support. If the app exits during the test, preserve the device crash report too.

## Validation

`dotnet run --project ios/EmitterChecks -c Release` checks the emitted ARM64
semantics against an independent small instruction decoder, golden instruction
bytes, and the actual C ABI's bounds checks. These checks run on non-ARM hosts.
They do not establish hardware JIT compatibility.

The iOS build additionally compiles C/assembly/Swift, checks signatures, validates
the native framework and Info.plist, and verifies `get-task-allow` is present in
the packaged entitlements. AltStore re-signing must preserve it on-device.

The local checks also compile all six guest programs using the upstream compiler
and reject invalid guest-memory ranges. On the Apple Silicon CI host, the same
managed library is compiled with NativeAOT for macOS and executes the guest suite
with four seeds: **100 translated guest executions**. The host harness uses
macOS `MAP_JIT` and per-thread write protection. The iOS app uses the already
validated StikDebug/TXM protocol and separate memory aliases. Passing on macOS
does not establish device compatibility for a new build. CI also compiles the
complete production CPU into a separate NativeAOT library and runs its five new
groups with four seeds, including concurrent threads, on Apple Silicon before
producing the iOS framework.

For desktop production CPU checks, prepare the locked source, then run
`dotnet run --project ios/RuntimeChecks -c Release`. These tests also run on x64;
only the Apple Silicon NativeAOT/device checks cover the actual ARM64 AOT path.

## Reported device results

On 7 November 2026, the user confirmed the original v0.1 IPA passed on both devices:

| Device | ARM64 probe | Development signing | TXM | JIT enabler |
| --- | --- | --- | --- | --- |
| iPhone 16 | All four inputs passed | Ready | Present | StikDebug |
| M1 11-inch iPad | All four inputs passed | Ready | Present | StikDebug |

These are user-reported results for the [first validated prototype build](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42386337979),
from commit `235f4b0b5ec132061cca7b62a0fe009ec7052b48`. Exact OS build numbers
were not captured. This verifies the arithmetic/code-emission probe; guest-code
translation, graphics, and game compatibility were not covered by that build.

The user subsequently reported all 25 v0.2 guest cases passed on **both devices**,
and supplied an iPad screenshot showing the six passing groups, signing ready,
TXM present and StikDebug selected. The v0.2 CI build is
[run 42389244296](https://github.com/vigneshmaneesh/ryu-ios/actions/runs/42389244296).
v0.3 production CPU hardware results remain pending.

## Next porting milestones

- Validate the v0.3 production CPU groups and enlarged prepared-memory pool on
  both devices, including a second run and shared memory diagnostics.
- Adapt memory reservation, aliasing, signal handling, and guest address spaces.
- Bring up the emulator services and sandboxed file/firmware/key import.
- Port the Vulkan renderer through an iOS MoltenVK build and a Metal surface.
- Add iOS audio, touch/game controllers, lifecycle handling and memory limits.
- Test game compatibility and performance separately on each device.

Existing desktop projects are unchanged. The iOS proof is deliberately built
separately from the desktop solution while the remaining core is being ported.

## References

- [StikDebug integration protocol](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md)
- [.NET NativeAOT iOS frameworks](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/ios-like-platforms/creating-and-consuming-custom-frameworks)
- [GitHub standard public runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [GitHub artifact storage billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

Ryujinx source remains under the repository's MIT license; its notice is packaged
inside the app. StikDebug is used as an external tool; its implementation is not
embedded in this app.
