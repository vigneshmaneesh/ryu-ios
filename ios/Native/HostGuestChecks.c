// Execute the same NativeAOT guest suite on the Apple Silicon CI host.
// iOS TXM activation is covered separately by the IPA's device test.
#include "JITBridge.h"
#include <errno.h>
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

static void begin_write(void) { pthread_jit_write_protect_np(0); }
static void publish(void *address, uintptr_t size) {
    sys_icache_invalidate(address, size);
    pthread_jit_write_protect_np(1);
}

int main(void) {
    const size_t capacity = 256 * 1024;
    void *code = mmap(NULL, capacity, PROT_READ | PROT_WRITE | PROT_EXEC,
                      MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (code == MAP_FAILED) { fprintf(stderr, "JIT allocation failed: %s\n", strerror(errno)); return 1; }
    uint32_t seeds[] = {0, 42, UINT32_MAX, 0x12345678};
    for (size_t index = 0; index < sizeof(seeds) / sizeof(seeds[0]); index++) {
        uint8_t report[1024] = {0};
        int32_t status = ryu_guest_suite(code, code, capacity, begin_write, publish,
                                        seeds[index], report, sizeof(report));
        printf("Seed %u:\n%s\n", seeds[index], (const char *)report);
        if (status != 0) { munmap(code, capacity); return 1; }
    }
    munmap(code, capacity);
    puts("PASS: 100 translated guest executions on Apple Silicon NativeAOT.");
    return 0;
}
