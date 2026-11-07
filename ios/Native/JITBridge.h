#ifndef RYU_JIT_BRIDGE_H
#define RYU_JIT_BRIDGE_H
#include <stddef.h>
#include <stdint.h>

enum RyuJITStage {
    RYU_JIT_IDLE, RYU_JIT_WAITING, RYU_JIT_PREPARING, RYU_JIT_EMITTING,
    RYU_JIT_EXECUTING, RYU_JIT_PASSED, RYU_JIT_FAILED, RYU_JIT_CANCELLED
};

// TXM detection: 1 = present, 0 = absent, -1 = unknown. Unknown must block activation.
int ryu_txm_presence(void);
// Signing status: 1 = get-task-allow, 0 = absent, -1 = query failed.
int ryu_debug_entitlement(void);
int ryu_jit_stage(void);
int ryu_jit_ready(void);
void ryu_jit_cancel(void);
// Blocking; call on a background queue. Returns 0 only after generated code passes.
int ryu_jit_run(int txm, uint32_t timeout_ms, uint32_t bias,
                uint64_t *result, char *error, size_t error_capacity);

// NativeAOT export from the repository's LightningJit ARM64 emitter.
int32_t ryu_emit_add(uint8_t *destination, uintptr_t capacity, uint32_t bias);
#endif
