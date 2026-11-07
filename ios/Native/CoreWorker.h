#ifndef RYU_CORE_WORKER_H
#define RYU_CORE_WORKER_H
#include <stddef.h>

// Desktop core initialization uses large by-value HID structures. Do not enter
// it on a Dispatch worker's small stack. This reserves virtual stack space;
// physical pages are committed on demand by pthreads.
#define RYU_CORE_STACK_SIZE (8u * 1024u * 1024u)
int ryu_core_on_thread(void *(*entry)(void *), void *context, size_t stack_size);
#endif
