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
- 60 settings: graphics scaling/filtering/AA/vsync/caching, system
  language/region/clock/RAM, docked mode, PTC/clock scalar, audio volume,
  integrity checks, missing-service handling, network/LDN parameters,
  GDB parameters, log levels and session log files. Values reach the upstream
  configuration, renderer and logging APIs; individual title compatibility is
  unverified. Software page tables select upstream ARMeilleure/JitEngine,
  including its PTC support; the host-mapped LightningJit cache limitation does
  not apply to this selected backend.
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
- Library search, sorting, format/favorite filters, grid/list, icon sizing,
  favorites, rename/removal, last played and play duration.
- Eight-player input snapshots and controller styles; saved reusable mappings,
  assignments, stick calibration, keyboard controls and raw keyboard/mouse HID.
- Controller/Core Motion sensor feeds, rumble through Core Haptics, sixteen
  stable touch IDs, right touch stick, L3/R3 and touch size/opacity controls.
  CI build 38 compiled these changes and passed its native integrated run;
  physical-device input acceptance is deferred to the complete candidate.
- Native profile/controller selection and error-app button prompts, optional
  profile/controller applet bypass settings, and preserved user-channel storage
  across ExecuteProgram/restart requests.
- In-game volume, vsync, docked mode and resolution controls, screenshots/PNG
  export/gallery, live session log, stop confirmation and focus-loss actions.
- Virtual amiibo ID scanning, dumped amiibo scanning and private key_retail.bin
  import through the upstream NFC/decryption implementation. Native controls
  expose the game's current tag-search state.

## Still required before a feature-complete candidate

- Library metadata batch refresh, folder imports,
  launch shortcuts, application data, extraction and XCI trimming tools.
- Controller profile deletion/import/export, hotkeys and movable touch layouts.
- Amiibo catalog/search, screenshot/file-management refinements, native applet
  acceptance and real-game multi-program compatibility.
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
