// StikDebug universal.js breakpoint ABI. Called only after debugger attachment.
#if defined(__arm64__)
.text
.p2align 2
.globl _ryu_jit_prepare_region
_ryu_jit_prepare_region:
    mov x16, #1
    brk #0xf00d
    ret

.p2align 2
.globl _ryu_jit_detach
_ryu_jit_detach:
    mov x16, #0
    brk #0xf00d
    ret
#endif
