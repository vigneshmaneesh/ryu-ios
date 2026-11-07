# Ryu iOS: first JIT milestone

This is an iOS 27 **proof of concept**, not a playable Switch emulator yet.
It is a native SwiftUI app for iPhone and iPad, with a small NativeAOT C# framework
that compiles the **actual LightningJit ARM64 assembler from this repository**.
After StikDebug activation it emits and executes `f(a, b) = a + b + bias` with
a new random bias each run, checking four inputs including unsigned overflow.

The proof establishes the native UI → AOT C# emitter → writable code alias →
prepared executable memory path. It does **not** yet translate guest programs,
boot Horizon, render Switch graphics, or load games.

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
4. A successful test displays **ARM64 test passed** and a computed result. Run it
   again to verify the prepared memory can be reused for newly generated code.
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

## Next porting milestones

- Replace this probe allocator with an iOS implementation of `IJitMemoryAllocator`
  and validate real guest instruction translation and managed callbacks.
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
