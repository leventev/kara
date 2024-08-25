.section .text

.option norvc

.altmacro
.set REGISTER_BYTES, 8

.macro writeGPR base_reg, i
    sd x\i, ((\i) * REGISTER_BYTES)(\base_reg)
.endm

.macro readGPR base_reg, i
    ld x\i, ((\i) * REGISTER_BYTES)(\base_reg)
.endm


.type trapHandlerSupervisor, @function
.global trapHandlerSupervisor
.align 4
trapHandlerSupervisor:
    # move *TrapData from sscratch into t6 and t6 into sscratch
    csrrw t6, sscratch, t6

    # save GPRs
    .set i, 1
    .rept 30
        writeGPR t6, %i
        .set i, i+1
    .endr

    # since t1 is already saved we can move *TrapData into it
    mv t1, t6
    # move the original t6 value back into t6
    csrr t6, sscratch
    writeGPR t1, 31

    # move *TrapData back into sscratch
    csrw sscratch, t1

    csrr a0, sepc
    csrr a1, scause
    csrr a2, sstatus
    csrr a3, stval
    mv a4, t1

    call handleTrap

    csrr t6, sscratch

    # load GPRs
    .set i, 1
    .rept 31
        readGPR t6, %i
        .set i, i + 1
    .endr

    sret
