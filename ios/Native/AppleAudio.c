#include "AppleAudio.h"
#include <AudioToolbox/AudioToolbox.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#define SLOT_COUNT 64
typedef struct { AudioQueueBufferRef buffer; atomic_bool busy; uint64_t ticket, frames; bool nonzero; } AudioSlot;
typedef struct { AudioQueueRef queue; uint32_t channels; AudioSlot slots[SLOT_COUNT]; atomic_ullong played, completed; } AudioOutput;
static atomic_ullong all_played, all_submitted, all_nonzero;

static void finished(void *context, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    (void)queue;
    AudioOutput *output = context;
    AudioSlot *slot = buffer->mUserData;
    atomic_fetch_add(&output->played, slot->frames);
    atomic_fetch_add(&all_played, slot->frames);
    if (slot->nonzero) atomic_fetch_add(&all_nonzero, slot->frames);
    atomic_store(&output->completed, slot->ticket);
    atomic_store(&slot->busy, false);
}
void *ryu_audio_open(uint32_t rate, uint32_t channels) {
    if (rate != 48000 || channels < 1 || channels > 2) return NULL;
    AudioOutput *output = calloc(1, sizeof(*output));
    if (!output) return NULL;
    atomic_init(&output->played, 0); atomic_init(&output->completed, 0);
    for (size_t i = 0; i < SLOT_COUNT; i++) atomic_init(&output->slots[i].busy, false);
    output->channels = channels;
    AudioStreamBasicDescription format = { .mSampleRate = rate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        .mBytesPerPacket = channels * 2, .mFramesPerPacket = 1, .mBytesPerFrame = channels * 2,
        .mChannelsPerFrame = channels, .mBitsPerChannel = 16 };
    OSStatus status = AudioQueueNewOutput(&format, finished, output, NULL, NULL, 0, &output->queue);
    if (status != noErr) { free(output); return NULL; }
    return output;
}
int ryu_audio_enqueue(void *handle, const uint8_t *data, uintptr_t size, uint64_t ticket) {
    AudioOutput *output = handle;
    if (!output || !data || size == 0 || size > 4 * 1024 * 1024 || size % (output->channels * 2)) return -1;
    for (size_t index = 0; index < SLOT_COUNT; index++) {
        AudioSlot *slot = &output->slots[index];
        bool expected = false;
        if (!atomic_compare_exchange_strong(&slot->busy, &expected, true)) continue;
        if (slot->buffer && slot->buffer->mAudioDataBytesCapacity < size) {
            AudioQueueFreeBuffer(output->queue, slot->buffer); slot->buffer = NULL;
        }
        OSStatus status = noErr;
        if (!slot->buffer) status = AudioQueueAllocateBuffer(output->queue, (UInt32)size, &slot->buffer);
        if (status == noErr) {
            memcpy(slot->buffer->mAudioData, data, size);
            slot->buffer->mAudioDataByteSize = (UInt32)size;
            slot->buffer->mUserData = slot;
            slot->ticket = ticket; slot->frames = size / (output->channels * 2);
            slot->nonzero = false;
            for (uintptr_t byte = 0; byte < size; byte++) if (data[byte]) { slot->nonzero = true; break; }
            status = AudioQueueEnqueueBuffer(output->queue, slot->buffer, 0, NULL);
            if (status == noErr) atomic_fetch_add(&all_submitted, slot->frames);
        }
        if (status != noErr) atomic_store(&slot->busy, false);
        return (int)status;
    }
    return -2;
}
int ryu_audio_control(void *handle, int action, float volume) {
    AudioOutput *output = handle;
    if (!output) return -1;
    if (action == 1) return (int)AudioQueueStart(output->queue, NULL);
    if (action == 0) return (int)AudioQueuePause(output->queue);
    return (int)AudioQueueSetParameter(output->queue, kAudioQueueParam_Volume, volume);
}
uint64_t ryu_audio_counter(void *handle, int kind) {
    if (!handle) return kind == 4 ? atomic_load(&all_nonzero) : kind == 3 ? atomic_load(&all_submitted) : atomic_load(&all_played);
    AudioOutput *output = handle;
    return kind == 1 ? atomic_load(&output->completed) : atomic_load(&output->played);
}
void ryu_audio_close(void *handle) {
    if (!handle) return;
    AudioOutput *output = handle;
    AudioQueueDispose(output->queue, true);
    free(output);
}
