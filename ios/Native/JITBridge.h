#ifndef RYU_JIT_BRIDGE_H
#define RYU_JIT_BRIDGE_H
#include <stddef.h>
#include <stdint.h>

// Metal layer is retained by the caller until this synchronous call returns.
int ryu_graphics_check(const char *library, void *metal_layer, int width, int height,
    const char *directory, char *report, size_t report_capacity);
void ryu_graphics_cancel(void);
// Reset cancellation on the UI thread before scheduling the synchronous check.
void ryu_graphics_prepare(void);
int ryu_homebrew_run(const char *library, void *metal_layer, int width, int height,
    const char *program, const char *directory, char *report, size_t report_capacity);
uint64_t ryu_homebrew_frames(void);
void ryu_input_set(uint64_t buttons, int lx, int ly, int rx, int ry);
void ryu_input_player(int player, int connected, int type, uint64_t buttons, int lx, int ly, int rx, int ry);
void ryu_motion_set(int player, const float *values18);
void ryu_rumble_read(int player, float *values8);
void ryu_keyboard_set(uint64_t a, uint64_t b, uint64_t c, uint64_t d, int modifiers);
void ryu_mouse_set(int x, int y, uint32_t buttons, int sx, int sy, int connected);
void ryu_touch_finger(int finger, int down, int x, int y);
void ryu_touch_set(int down, int x, int y);
void ryu_input_reset(void);
void ryu_pause(int paused);
uint64_t ryu_audio_frames(void);
int ryu_content(int action, const char *source, const char *directory, char *report, size_t capacity);
int ryu_app(const char *directory, const char *request, char *report, size_t capacity);
void ryu_ui_poll(char *report, size_t capacity);
void ryu_ui_answer(int id, int accepted, const char *text);

enum RyuJITStage {
    RYU_JIT_IDLE, RYU_JIT_WAITING, RYU_JIT_PREPARING, RYU_JIT_EMITTING,
    RYU_JIT_EXECUTING, RYU_JIT_PASSED, RYU_JIT_FAILED, RYU_JIT_CANCELLED,
    RYU_JIT_TRANSLATING, RYU_JIT_GUEST_EXECUTING
};

// TXM detection: 1 = present, 0 = absent, -1 = unknown. Unknown must block activation.
int ryu_txm_presence(void);
// Signing status: 1 = get-task-allow, 0 = absent, -1 = query failed.
int ryu_debug_entitlement(void);
int ryu_jit_stage(void);
int ryu_jit_ready(void);
void ryu_jit_cancel(void);
uint64_t ryu_memory_footprint(void);
uint64_t ryu_available_memory(void);
uint64_t ryu_prepared_code_capacity(void);
// Independent filesystem/account and Vulkan roundtrip checks; no JIT required.
int ryu_backend_check(const char *data_directory, char *report, size_t report_capacity);
int ryu_horizon_check(const char *data_directory, char *report, size_t report_capacity);
// Blocking; call on a background queue. Returns 0 only after generated code passes.
int ryu_jit_run(int txm, uint32_t timeout_ms, uint32_t bias,
                uint64_t *result, char *error, size_t error_capacity);

// NativeAOT export from the repository's LightningJit ARM64 emitter.
int32_t ryu_emit_add(uint8_t *destination, uintptr_t capacity, uint32_t bias);
int32_t ryu_guest_suite(void *writable, void *executable, uintptr_t capacity,
                       void (*begin_write)(void), void (*publish)(void *, uintptr_t),
                       uint32_t seed, uint8_t *report, uintptr_t report_capacity);
#endif
