#include "CoreWorker.h"
#include <pthread.h>

int ryu_core_on_thread(void *(*entry)(void *), void *context, size_t stack_size) {
    pthread_attr_t attributes;
    int status = pthread_attr_init(&attributes);
    if (status != 0) return status;
    status = pthread_attr_setstacksize(&attributes, stack_size);
    pthread_t thread;
    if (status == 0) status = pthread_create(&thread, &attributes, entry, context);
    pthread_attr_destroy(&attributes);
    if (status != 0) return status;
    // The synchronous caller owns context and all referenced buffers until join.
    return pthread_join(thread, NULL);
}
