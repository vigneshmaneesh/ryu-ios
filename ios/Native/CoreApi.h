#ifndef RYU_CORE_API_H
#define RYU_CORE_API_H
#include <stddef.h>
#include <stdint.h>

// Version 1: all strings UTF-8, caller-owned buffers, synchronous calls.
// Return 0 on success; failures write a bounded, NUL-terminated report.
// The caller keeps both aliases and callbacks alive throughout the call.
uint32_t ryu_core_abi_version(void);
int32_t ryu_core_services_check(const uint8_t *directory, uint8_t *report, uintptr_t report_capacity);
int32_t ryu_core_check(void *writable, void *executable, uintptr_t capacity,
                      void (*begin_write)(void), void (*publish)(void *, uintptr_t),
                      uint32_t seed, uint8_t *report, uintptr_t report_capacity);
#endif
