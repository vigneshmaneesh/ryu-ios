#ifndef RYU_APPLE_AUDIO_H
#define RYU_APPLE_AUDIO_H
#include <stddef.h>
#include <stdint.h>
void *ryu_audio_open(uint32_t rate, uint32_t channels);
int ryu_audio_enqueue(void *handle, const uint8_t *data, uintptr_t size, uint64_t ticket);
int ryu_audio_control(void *handle, int action, float volume);
uint64_t ryu_audio_counter(void *handle, int kind);
void ryu_audio_close(void *handle);
#endif
