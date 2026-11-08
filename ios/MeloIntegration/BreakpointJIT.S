// Reviewed StikDebug universal.js breakpoint ABI; no opaque JIT framework.
.text
.p2align 2
.globl _BreakGetJITMapping
_BreakGetJITMapping:
    mov x16, #1
    brk #0xf00d
    ret

.p2align 2
.globl _BreakMarkJITMapping
_BreakMarkJITMapping:
    mov x1, x0
    mov x0, #0
    b _BreakGetJITMapping

.p2align 2
.globl _BreakJITDetach
_BreakJITDetach:
    mov x16, #0
    brk #0xf00d
    ret
