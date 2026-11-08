# Native iOS parity work

Target: the Ryubing revision in `upstream.lock.json`, configuration format 73.
`parity-inventory.json` inventories all 99 serialized configuration properties
and 153 occurrences of UI commands/handlers. Occurrences can refer to the same
feature. This is an audit inventory, not a claim of 153 implemented features.

Device-test requests are deferred until the complete candidate requested by the
user. Public GitHub Actions continues compilation, NativeAOT and integrated
homebrew checks during development. Commercial game compatibility has not yet
been established; v0.9.1's specific XCI retry remains unconfirmed.

## Implemented for the parity branch

- Persistent global/per-imported-title configuration with inheritance, reset,
  validation, atomic saves and a native searchable settings editor.
- 51 engine settings: graphics scaling/filtering/AA/vsync/caching, system
  language/region/clock/RAM, docked mode, PTC/clock scalar, audio volume,
  integrity checks, missing-service handling, network/LDN parameters,
  GDB parameters, log levels and session log files. Values reach the upstream
  configuration, renderer and logging APIs; individual title compatibility is
  unverified. PTC applicability to the selected CPU backend needs audit.
- Optional threaded graphics backend with an owned, joined GPU-worker lifecycle.
- Decrypted base-container metadata and icons through LibHac, using the same
  complete-read adapter as the game loader.
- Update registration/selection/removal and DLC registration/enablement using
  the exact upstream `updates.json`/`dlc.json` formats and title-ID checks.
- Profile creation, selection, renaming, JPEG avatars and confirmed deletion
  through the real account manager. The default recovery account is retained.
- Save listing, ZIP export, journaled ZIP restore and confirmed deletion through
  the actual save index. Interrupted restores recover before services mount.
- Per-title mod ZIP import/enable/remove and build-ID cheat import/enablement.
  Mod metadata and enabled-cheat names use the upstream loader's formats.
- Atmosphere VM integer operations and 68 closed generic instruction
  constructors adapted for NativeAOT. Automated checks execute a real cheat
  program with key conditionals, arithmetic and 8/16/32/64-bit memory writes.

## Still required before a feature-complete candidate

- Library search/sort/grid/favorites/play time, metadata refresh, folder imports,
  launch shortcuts, application data, extraction and XCI trimming tools.
- All players/controller types, mapping and profiles, motion, rumble,
  keyboard/mouse, hotkeys and touch-layout settings.
- In-game quick settings, screenshots, amiibo scanning/cabinet and program
  transitions; lifecycle/pause behavior and native controller/profile applets.
- LAN/LDN browsing and connection controls; network-specific AOT review.
- Shader/PTC cache tools, dirty hacks, logging class filters, configuration
  import/export, localization, theme and remaining frontend settings.
- Complete automated integration and packaging review; then consolidated
  physical-device acceptance and commercial-title compatibility work.

## Platform substitutions and limits

The iOS backend is Vulkan through MoltenVK/Metal on the integrated Apple GPU.
This port uses software page tables and prepared StikDebug JIT memory.
Desktop OpenGL, an unjailed hypervisor, desktop Discord RPC, arbitrary desktop
window positioning and in-place desktop executable updates are unavailable.
Native navigation/window management and AltStore IPA installation replace the
corresponding desktop flows. Unavailable modes must never appear as working
toggles. These limits prevent a literal promise that every desktop execution
mode will exist on iOS.

Upstream updates remain pinned lock changes with reviewed overlays. The parity
audit is regenerated from that exact tree, making additions/removals visible.
