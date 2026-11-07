#include "CoreApi.h"
#include "CoreWorker.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    const char *directory;
    int status;
} StartupWork;

static void *check_startup(void *context) {
    StartupWork *work = context;
    printf("Native core worker stack: %zu bytes\n", pthread_get_stacksize_np(pthread_self()));
    fflush(stdout);
    for (int run = 0; run < 2; run++) {
        uint8_t report[4096] = {0};
        work->status = ryu_core_startup_check((const uint8_t *)work->directory, report, sizeof(report));
        printf("Startup run %d: %s\n", run + 1, (const char *)report);
        fflush(stdout);
        if (work->status != 0) break;
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    StartupWork work = { argv[1], -1 };
    size_t stack_size = strtoul(argv[2], NULL, 10);
    int status = ryu_core_on_thread(check_startup, &work, stack_size);
    if (status != 0) {
        fprintf(stderr, "Could not create/join startup worker: %d\n", status);
        return 3;
    }
    return work.status == 0 ? 0 : 1;
}
