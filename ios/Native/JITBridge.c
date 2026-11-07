#include "JITBridge.h"
#include "CoreApi.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <os/proc.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

// csops is an iOS SPI used here only against this process, in a sideloaded build.
extern int csops(pid_t pid, unsigned int operation, void *address, size_t size);
extern void *ryu_jit_prepare_region(void *address, size_t length);
extern void ryu_jit_detach(void);

static const uint32_t CS_OPS_STATUS = 0;
static const uint32_t CS_GET_TASK_ALLOW = 0x00000004;
static const uint32_t CS_DEBUGGED = 0x10000000;
static atomic_int stage = RYU_JIT_IDLE;
static atomic_bool cancelled = false;
static atomic_bool ready = false;
static atomic_flag running = ATOMIC_FLAG_INIT;
static vm_address_t executable = 0;
static vm_address_t writable = 0;
static _Atomic(vm_size_t) allocation_size = 0;

static int signing_flags(uint32_t *flags) {
    *flags = 0;
    return csops(getpid(), CS_OPS_STATUS, flags, sizeof(*flags));
}

int ryu_debug_entitlement(void) {
    uint32_t flags;
    if (signing_flags(&flags) != 0) return -1;
    return (flags & CS_GET_TASK_ALLOW) != 0;
}

int ryu_txm_presence(void) {
    // Resolve the system IOKit entry points without depending on private SDK headers.
    void *library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (library == NULL) return -1;
    typedef uint32_t (*EntryFromPath)(mach_port_t, const char *);
    typedef CFTypeRef (*CopyProperty)(uint32_t, CFStringRef, CFAllocatorRef, uint32_t);
    typedef kern_return_t (*ReleaseEntry)(uint32_t);
    EntryFromPath find = (EntryFromPath)dlsym(library, "IORegistryEntryFromPath");
    CopyProperty copy = (CopyProperty)dlsym(library, "IORegistryEntryCreateCFProperty");
    ReleaseEntry release = (ReleaseEntry)dlsym(library, "IOObjectRelease");
    int present = -1;
    if (find != NULL && copy != NULL && release != NULL) {
        uint32_t entry = find(MACH_PORT_NULL, "IODeviceTree:/chosen/memory-map");
        if (entry != 0) {
            CFTypeRef keys = copy(entry, CFSTR("IORegistryEntryPropertyKeys"), kCFAllocatorDefault, 0);
            release(entry);
            if (keys != NULL && CFGetTypeID(keys) == CFArrayGetTypeID()) {
                CFArrayRef array = (CFArrayRef)keys;
                present = CFArrayContainsValue(array, CFRangeMake(0, CFArrayGetCount(array)), CFSTR("TXM")) ? 1 : 0;
            }
            if (keys != NULL) CFRelease(keys);
        }
    }
    dlclose(library);
    return present;
}

int ryu_jit_stage(void) { return atomic_load(&stage); }
int ryu_jit_ready(void) { return atomic_load(&ready); }
void ryu_jit_cancel(void) { atomic_store(&cancelled, true); }
uint64_t ryu_available_memory(void) { return (uint64_t)os_proc_available_memory(); }
uint64_t ryu_prepared_code_capacity(void) { return (uint64_t)allocation_size; }
uint64_t ryu_memory_footprint(void) {
    task_vm_info_data_t info = {0};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return info.phys_footprint;
}

static uint64_t milliseconds(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (uint64_t)time.tv_sec * 1000 + (uint64_t)time.tv_nsec / 1000000;
}

static int fail(char *error, size_t capacity, const char *message, int code) {
    if (error != NULL && capacity > 0) snprintf(error, capacity, "%s (%d)", message, code);
    atomic_store(&stage, code == ECANCELED ? RYU_JIT_CANCELLED : RYU_JIT_FAILED);
    atomic_flag_clear(&running);
    return code != 0 ? code : -1;
}

static void discard_regions(void) {
    if (writable != 0) vm_deallocate(mach_task_self(), writable, allocation_size);
    if (executable != 0) vm_deallocate(mach_task_self(), executable, allocation_size);
    writable = executable = 0;
    allocation_size = 0;
}

static kern_return_t allocate_regions(int txm) {
    // Virtual reservation; the upstream code cache touches physical pages on demand.
    // Keep the existing compiler conformance suite in a separate 1 MiB prefix.
    allocation_size = (vm_size_t)(257UL * 1024 * 1024);
    kern_return_t status;
    bool script_active = txm == 1;
    if (script_active) {
        // universal.js allocates and prepares this RX mapping through debugserver.
        executable = (vm_address_t)ryu_jit_prepare_region(NULL, (size_t)allocation_size);
        status = executable == 0 ? KERN_RESOURCE_SHORTAGE : KERN_SUCCESS;
    } else {
        status = vm_allocate(mach_task_self(), &executable, allocation_size, VM_FLAGS_ANYWHERE);
        if (status == KERN_SUCCESS)
            status = vm_protect(mach_task_self(), executable, allocation_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    }

    vm_prot_t current = 0, maximum = 0;
    if (status == KERN_SUCCESS) {
        status = vm_remap(mach_task_self(), &writable, allocation_size, 0,
                               VM_FLAGS_ANYWHERE, mach_task_self(), executable,
                               FALSE, &current, &maximum, VM_INHERIT_NONE);
    }
    if (status == KERN_SUCCESS) {
        status = vm_protect(mach_task_self(), writable, allocation_size, FALSE, VM_PROT_READ | VM_PROT_WRITE);
    }
    // Complete the script handshake even if alias creation failed, before reporting.
    if (script_active) ryu_jit_detach();
    if (status != KERN_SUCCESS) discard_regions();
    return status;
}

static void begin_code_write(void) {
    atomic_store(&stage, RYU_JIT_TRANSLATING);
}

static void publish_code(void *address, uintptr_t length) {
    atomic_thread_fence(memory_order_seq_cst);
    sys_icache_invalidate(address, length);
    atomic_store(&stage, RYU_JIT_GUEST_EXECUTING);
}

int ryu_jit_run(int txm, uint32_t timeout_ms, uint32_t bias,
                uint64_t *result, char *error, size_t error_capacity) {
    if (atomic_flag_test_and_set(&running)) return EBUSY;
    atomic_store(&cancelled, false);
    if (error != NULL && error_capacity > 0) error[0] = '\0';
    if (result == NULL) return fail(error, error_capacity, "Missing result buffer", EINVAL);
    *result = 0;
    if (txm != 0 && txm != 1) return fail(error, error_capacity, "Cannot determine TXM status", ENOTSUP);
    if (ryu_debug_entitlement() != 1)
        return fail(error, error_capacity, "Install using AltStore Classic or SideStore with get-task-allow", EPERM);

    if (executable == 0) {
        atomic_store(&stage, RYU_JIT_WAITING);
        uint64_t deadline = milliseconds() + timeout_ms;
        while (true) {
            if (atomic_load(&cancelled)) return fail(error, error_capacity, "JIT activation cancelled", ECANCELED);
            uint32_t flags;
            if (signing_flags(&flags) != 0)
                return fail(error, error_capacity, "Could not read debugger status", errno);
            if ((flags & CS_DEBUGGED) != 0) break;
            if (milliseconds() >= deadline)
                return fail(error, error_capacity, "Timed out waiting for StikDebug; check LocalDevVPN and pairing", ETIMEDOUT);
            struct timespec pause = {.tv_sec = 0, .tv_nsec = 50000000};
            nanosleep(&pause, NULL);
        }
        atomic_store(&stage, RYU_JIT_PREPARING);
        kern_return_t status = allocate_regions(txm);
        if (status != KERN_SUCCESS)
            return fail(error, error_capacity, "Could not prepare JIT memory; restart the app before retrying", status);
    }

    atomic_store(&stage, RYU_JIT_EMITTING);
    int32_t code_size = ryu_emit_add((uint8_t *)writable, (uintptr_t)allocation_size, bias);
    if (code_size <= 0 || (vm_size_t)code_size > allocation_size)
        return fail(error, error_capacity, "Ryujinx ARM64 code generation failed", code_size);
    // Distinct RW and RX aliases preserve W^X. Publish the new instructions before calling.
    atomic_thread_fence(memory_order_seq_cst);
    sys_icache_invalidate((void *)executable, (size_t)code_size);

    atomic_store(&stage, RYU_JIT_EXECUTING);
    typedef uint64_t (*GeneratedAdd)(uint64_t, uint64_t);
    GeneratedAdd function = (GeneratedAdd)executable;
    const uint64_t a[] = {20, 0, UINT64_MAX, UINT64_C(0x1234567890abcdef)};
    const uint64_t b[] = {22, 0, 1, UINT64_C(0xfedcba0987654321)};
    for (size_t index = 0; index < sizeof(a) / sizeof(a[0]); index++) {
        uint64_t actual = function(a[index], b[index]);
        if (actual != a[index] + b[index] + bias)
            return fail(error, error_capacity, "Generated ARM64 code returned an unexpected value", EIO);
        if (index == 0) *result = actual;
    }
    atomic_store(&stage, RYU_JIT_TRANSLATING);
    const size_t diagnostic_capacity = 1024 * 1024;
    int32_t guest_status = ryu_guest_suite((void *)writable, (void *)executable,
        diagnostic_capacity, begin_code_write, publish_code, bias,
        (uint8_t *)error, error_capacity);
    if (guest_status != 0) {
        atomic_store(&stage, RYU_JIT_FAILED);
        atomic_flag_clear(&running);
        return guest_status;
    }
    if (ryu_core_abi_version() != 1)
        return fail(error, error_capacity, "Unsupported production core ABI", ENOTSUP);
    size_t used = error != NULL && error_capacity > 0 ? strnlen(error, error_capacity) : 0;
    if (used + 1 < error_capacity) { error[used++] = '\n'; error[used] = '\0'; }
    int32_t core_status = ryu_core_check((void *)(writable + diagnostic_capacity),
        (void *)(executable + diagnostic_capacity), allocation_size - diagnostic_capacity,
        begin_code_write, publish_code, bias, (uint8_t *)error + used, error_capacity - used);
    if (core_status != 0) {
        atomic_store(&stage, RYU_JIT_FAILED);
        atomic_flag_clear(&running);
        return core_status;
    }
    atomic_store(&ready, true);
    atomic_store(&stage, RYU_JIT_PASSED);
    atomic_flag_clear(&running);
    return 0;
}
