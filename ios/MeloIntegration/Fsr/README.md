# Portable FSR1 shader update

The iOS Vulkan path uses the colour-only EASU/RCAS shader header from
[AMD FSR SDK 2.4.0](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/releases/tag/v2.4.0),
commit `7539ae8b6568ad29ed78a753404351daf3b5cca7`:
`Kits/FidelityFX/upscalers/fsr3/include/gpu/fsr1/ffx_fsr1.h`.
The original MIT notice is retained in the vendored file and shipped in the IPA.

This is an updated **FSR1 spatial shader**, not FSR4 ML, a temporal scaler,
or frame generation. The version label identifies the SDK revision that
supplied the actual shader. It does not claim the whole FSR SDK runtime
or its desktop ML binaries run on iOS.

`ffx_glsl_compat.h` maps the GPU header's types and basic mathematical operations
to standard GLSL full-precision operations. The iOS adapters preserve the
renderer descriptor bindings and its 16x16-pixel dispatch coverage, with explicit
edge bounds and clamped RCAS taps. Exact reciprocal functions replace the
header's optional reciprocal approximation helpers.

The GLSL is compiled into Vulkan 1.1 SPIR-V using Khronos glslang 16.6.0.
The official compiler download is pinned by SHA-256 on both Windows and macOS.
The shaders execute through Vulkan/MoltenVK on the GPU. There is no x86 runtime,
AMD driver DLL, CPU SIMD assumption, or AMD-only wave instruction requirement.

FSR2/3 temporal upscaling needs per-frame depth, motion, jitter and history
metadata that this emulator's present-only scaler does not expose.
FSR4 desktop ML/runtime requirements are not a compatible replacement for this
iPhone/iPad path. A larger renderer integration would be needed for those.

Quality names are labels for ratios: Native 1.0x, Ultra Quality 1.3x,
Quality 1.5x, Balanced 1.7x, Performance 2.0x, Ultra Performance 3.0x.
As requested, no preset silently changes the game's internal render resolution.
FSR automatically fits the display; the settings show a ratio guide separately
from FSR sharpness. The existing OpenGL FSR path is retained and identified as
legacy in telemetry; the updated shaders above belong to the iOS Vulkan path.
