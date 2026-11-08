# Port boundaries and remaining work

The app uses native SwiftUI, a C/assembly StikDebug coordinator and a versioned
NativeAOT interface. The complete core source is fetched at an immutable revision;
checked overlays live in `scripts/prepare_core.py`. Desktop source is unchanged.

The initial production CPU path uses upstream ARMeilleure with software page
tables. This avoids adopting desktop signal-handler ABI layouts on iOS. Both JIT
caches support explicit writes through prepared aliases, including the future
LightningJit path. Existing compiler and CPU execution regressions remain required
when changing the allocator or updating upstream.

Legacy Horizon service discovery and command dispatch use reflection. The AOT
descriptor preserves their constructors/methods. GPU macro execution selects the
existing interpreter when dynamic .NET code is unavailable. Optional tamper/cheat
generic instantiation still has AOT analysis warnings and is not an enabled iOS
feature. Do not suppress those warnings and claim the entire desktop feature set.

`HorizonProbe` runs an authored NRO through the actual kernel, scheduler, process
loader and system calls. Its diagnostic renderer throws on graphics access and
its audio driver is the upstream dummy driver. It is solely a bounded kernel
conformance workload; it is not a renderer or game-launch fallback. It first
initializes the shader-cache readiness gate that the CPU waits on, even though
the workload makes no GPU calls. Successful teardown and a second run are required.

The host stack is part of the core integration contract. Upstream HID initialization
builds a 0x40000-byte shared-memory struct by value, with nested temporary values.
The iOS bridge enters the kernel on an explicit 8 MiB pthread stack and joins it
before returning caller-owned buffers. Do not invoke that constructor directly
from a Dispatch worker. The iOS runtime CI check compares a 512 KiB control with
the explicit-stack worker and requires two successful construction/teardown runs.
It does not execute guest code or establish physical-device compatibility.

Checked startup overlays provide an optional `StartupDiagnostics.Checkpoint`
callback in HLE. The app flushes those constructor checkpoints to its journal,
including the actual native stack size, so fatal native failures can be narrowed
after relaunch. An unset callback preserves desktop behavior. Any upstream
constructor change must pass the overlay's exact-match checks during an update.

Still required for a usable game release:

- Validate the new upstream VulkanRenderer / retained CAMetalLayer / swapchain bridge on devices, then wire real guest GPU command submission and frame presentation.
- Validate shader translation, capabilities, texture formats and caches on both GPUs.
- Integrate native audio and its session/interruption lifecycle.
- Connect touch, controllers, motion and native applet/software-keyboard UI.
- Add transactional firmware, key and title-update imports; connect game launch.
- Verify saves and per-title settings, pause/resume, backgrounding and memory pressure.
- Boot Tomodachi Life: Living the Dream and measure correctness, RAM, speed and heat.
- Establish both-device regressions and finish release notices, packaging and rollback.

The fixed numbered scope and current evidence are maintained in `MILESTONES.md`
and `DEVICE_RESULTS.md`. Phase 22 is not complete until the usable emulator and
device/game acceptance criteria actually pass.

v0.6 renderer bring-up uses the actual upstream Vulkan backend, not the small C
Vulkan readback probe. Checked overlays enable the MoltenVK capability path on
iOS, condition portability enumeration on advertised support, bound swapchain
acquisition for lifecycle cancellation, check presentation results and count
accepted frames. Silk.NET commands bind directly from the embedded signed framework,
bypassing its default `__Internal` loader, which fails under iOS NativeAOT. Helper
shaders use upstream embedded SPIR-V binaries. The optional
GLSL compiler is not packaged; iOS rejects that path explicitly. v0.7 connects guest SPIR-V translation, GPU command submission and homebrew display. Its first Apple NativeAOT smoke boot presents 178 frames and shuts down cleanly; device homebrew display and game compatibility remain unverified.

v0.7's first real guest smoke boot presented an emulated GPU frame at
21:24:02 UTC in run 42415436349. The deko3d program compiled and reached its
normal libnx exit, but applet AM's `ISelfController.Exit` was an upstream stub,
leaving libnx asleep. The iOS overlay now exposes an application-exit request
on Switch; the frontend observes it and performs kernel/GPU teardown on its own
thread. No termination is performed inside the IPC service callback.

v0.7.1 corrects NRO input access for signed iOS resources. The loader explicitly
opens NROs read-only, retaining the stream for executable/assets/RomFS reads. The
normal one-boot smoke uses an enforced read-only NRO to cover the reported device
failure; extended regressions remain opt-in.

v0.8 routes guest audio through IHardwareDeviceDriver to Apple's AudioQueue. PCM
is copied into bounded native buffers; completion callbacks update atomics only.
The managed audio driver's poller signals upstream buffer completion. Existing
compatibility code downmixes six channels to stereo; audio input falls back to
the upstream dummy input path. UIKit single-touch input uses Switch's 1280x720
coordinate space; only the emulation worker writes HID lifos. Player one is a
Pro Controller. Physical face buttons map by Switch positions. Pausing uses
Horizon.TogglePauseEmulation, including audio pause and guest tick suspension.
Closing/backgrounding clears controls, cancels execution and retains the Metal
surface until the native worker joins. Firmware/key import is still absent.

## Commercial game launch integration

v0.9 adds System files: import prod.keys/title.keys and install a firmware ZIP or
an XCI with an update partition. The upstream verifier checks the firmware before
the installed directory is touched. A pending journal and same-volume backup
preserve the previous firmware across a failed or interrupted installation.
Key validation completes in a staging directory and key material is excluded
from shareable diagnostics. All data stays under the app's private emulator root.
Library Play now dispatches NSP/XCI to their real loaders and NSO/NRO to LoadNxo.
Missing system files return a setup error without invalidating the prepared JIT.
The applet bridge queues native message/text prompts and cancels waiters during
shutdown; the default emulated profile answers player-selection requests.
Title updates, DLC, program transitions, multi-player setup, motion and broad
commercial compatibility remain incomplete. No user game/firmware/key dump has
been used in CI. The CI check uses synthetic import/recovery failures plus one
integrated public-domain homebrew play session.
