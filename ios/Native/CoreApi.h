#ifndef RYU_CORE_API_H
#define RYU_CORE_API_H
#include <stddef.h>
#include <stdint.h>

// Version 1: all strings UTF-8, caller-owned buffers, synchronous calls.
// Return 0 on success; failures write a bounded, NUL-terminated report.
// The caller keeps both aliases and callbacks alive throughout the call.
uint32_t ryu_core_abi_version(void);
int32_t ryu_core_session_command(int command, double value, const uint8_t *text);
void ryu_core_session_poll(uint8_t *report, uintptr_t capacity);
int32_t ryu_core_app(const uint8_t *directory, const uint8_t *request, uint8_t *report, uintptr_t capacity);
void ryu_core_ui_poll(uint8_t *report, uintptr_t capacity);
void ryu_core_ui_answer(int id, int accepted, const uint8_t *text);
int32_t ryu_core_content(int action, const uint8_t *source, const uint8_t *directory, uint8_t *report, uintptr_t capacity);
int32_t ryu_core_imports_check(const uint8_t *directory, uint8_t *report, uintptr_t capacity);
uint64_t ryu_core_guest_frames(void);
void ryu_core_input_set(uint64_t buttons, int lx, int ly, int rx, int ry);
void ryu_core_input_player(int player, int connected, int type, uint64_t buttons, int lx, int ly, int rx, int ry);
void ryu_core_motion_set(int player, const float *values18);
void ryu_core_rumble_read(int player, float *values8);
void ryu_core_keyboard_set(uint64_t a, uint64_t b, uint64_t c, uint64_t d, int modifiers);
void ryu_core_mouse_set(int x, int y, uint32_t buttons, int sx, int sy, int connected);
void ryu_core_touch_finger(int finger, int down, int x, int y);
void ryu_core_touch_set(int down, int x, int y);
void ryu_core_input_reset(void);
void ryu_core_pause(int paused);
int32_t ryu_core_audio_configure(void *(*open)(uint32_t, uint32_t),
    int (*enqueue)(void *, const uint8_t *, uintptr_t, uint64_t),
    int (*control)(void *, int, float), uint64_t (*counter)(void *, int), void (*close)(void *));
int32_t ryu_core_homebrew_run(void *writable, void *executable, uintptr_t capacity,
    void (*begin_write)(void), void (*publish)(void *, uintptr_t),
    const uint8_t *library, void *metal_layer, int width, int height,
    int (*create_surface)(void *instance, void *layer, uint64_t *surface), int (*cancelled)(void),
    const uint8_t *program, const uint8_t *directory, uint8_t *report, uintptr_t report_capacity);
int32_t ryu_core_graphics_check(const uint8_t *library, void *metal_layer, int width, int height,
    int (*create_surface)(void *instance, void *layer, uint64_t *surface), int (*cancelled)(void),
    const uint8_t *directory, uint8_t *report, uintptr_t report_capacity);
int32_t ryu_core_services_check(const uint8_t *directory, uint8_t *report, uintptr_t report_capacity);
int32_t ryu_core_startup_check(const uint8_t *directory, uint8_t *report, uintptr_t report_capacity);
int32_t ryu_core_horizon_check(void *writable, void *executable, uintptr_t capacity,
    void (*begin_write)(void), void (*publish)(void *, uintptr_t),
    const uint8_t *directory, uint8_t *report, uintptr_t report_capacity);
int32_t ryu_core_check(void *writable, void *executable, uintptr_t capacity,
                      void (*begin_write)(void), void (*publish)(void *, uintptr_t),
                      uint32_t seed, uint8_t *report, uintptr_t report_capacity);
#endif
