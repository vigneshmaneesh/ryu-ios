# Updating the emulator core

`upstream.lock.json` fixes the complete source revision. On 7 November 2026,
all 4,240 checked source/build files in the supplied desktop source matched
`a61a42681119bf15fe8f3297677ae48bda83e70f` after normalizing text line endings.

`python ios/scripts/prepare_core.py` fetches that commit through Git, exports it
into `ios/build/upstream`, then applies the platform adapter. It does not modify
the supplied `src` tree. `--offline` works when the locked commit's Git objects
are already available. A partial Git cache may still need network access to
materialize blobs on its first export.

The adapter exposes prepared-code allocation, writes both upstream JIT caches
through a separate writable alias, and routes ordinary iOS data mappings through
the Darwin implementation. It deliberately does not turn on desktop signal
handlers or Apple hypervisor support on iOS. Initial production CPU validation
uses the existing software page-table engine.

Every text edit checks its exact match count. A changed upstream method fails
preparation with an **adapter conflict**, rather than silently applying a patch
at a guessed location. A generated SHA-256 manifest identifies the resulting
source files. Native callers use `ios/Native/CoreApi.h`, ABI version 1.

For an update:

1. Change the lock to a reviewed, full commit hash on a development branch.
2. Run preparation and resolve any explicit adapter conflicts.
3. Run compiler checks and production CPU checks on a desktop host.
4. Build and execute Apple Silicon NativeAOT checks, then compile/sign/verify the IPA.
5. Run JIT, homebrew and game regressions on **both** target devices.
6. Keep the previous working lock and IPA available for rollback before promoting the update.

This is a pinned dependency with a platform adapter. Many small upstream changes
will need little iOS work, but it is not guaranteed plug-and-play: CPU ABI,
memory, graphics and service changes can require adapter fixes or regress games.
Never advance the lock automatically just because a newer upstream commit exists.
