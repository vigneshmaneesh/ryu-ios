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

Still required for a usable game release:

- Wire the upstream Vulkan renderer to a retained CAMetalLayer and presentation.
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
