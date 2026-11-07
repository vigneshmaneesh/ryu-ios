#include "CoreApi.h"
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
    if (ryu_core_abi_version() != 1) { fputs("Unsupported core ABI\n", stderr); return 1; }
    const size_t capacity = 256UL * 1024 * 1024;
    void *code = mmap(NULL, capacity, PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (code == MAP_FAILED) { fprintf(stderr, "JIT mapping failed: %s\n", strerror(errno)); return 1; }
    uint32_t seeds[] = {0, 42, UINT32_MAX, 0x12345678};
    for (size_t i = 0; i < sizeof(seeds) / sizeof(seeds[0]); i++) {
        uint8_t report[2048] = {0};
        int status = ryu_core_check(code, code, capacity, begin_write, publish, seeds[i], report, sizeof(report));
        printf("Core seed %u:\n%s\n", seeds[i], report);
        if (status != 0) { munmap(code, capacity); return 1; }
    }
    munmap(code, capacity);
    puts("PASS: all production CPU checks on Apple Silicon NativeAOT.");
    return 0;
}
