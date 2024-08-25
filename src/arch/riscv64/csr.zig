const std = @import("std");

pub const CSR = enum(comptime_int) {
    // unprivileged floating point CSRs
    fflags = 0x001,
    frm = 0x002,
    fcsr = 0x003,

    // unprivileged counter/timers
    cycle = 0xC00,
    time = 0xC01,
    instret = 0xC02,
    hpmcounter3 = 0xC03,
    hpmcounter4 = 0xC04,
    hpmcounter5 = 0xC05,
    hpmcounter6 = 0xC06,
    hpmcounter7 = 0xC07,
    hpmcounter8 = 0xC08,
    hpmcounter9 = 0xC09,
    hpmcounter10 = 0xC0A,
    hpmcounter11 = 0xC0B,
    hpmcounter12 = 0xC0C,
    hpmcounter13 = 0xC0D,
    hpmcounter14 = 0xC0E,
    hpmcounter15 = 0xC0F,
    hpmcounter16 = 0xC10,
    hpmcounter17 = 0xC11,
    hpmcounter18 = 0xC12,
    hpmcounter19 = 0xC13,
    hpmcounter20 = 0xC14,
    hpmcounter21 = 0xC15,
    hpmcounter22 = 0xC16,
    hpmcounter23 = 0xC17,
    hpmcounter24 = 0xC18,
    hpmcounter25 = 0xC19,
    hpmcounter26 = 0xC1A,
    hpmcounter27 = 0xC1B,
    hpmcounter28 = 0xC1C,
    hpmcounter29 = 0xC1D,
    hpmcounter30 = 0xC1E,
    hpmcounter31 = 0xC1F,
    cycleh = 0xC80,
    timeh = 0xC81,
    instreth = 0xC82,
    hpmcounter3h = 0xC83,
    hpmcounter4h = 0xC84,
    hpmcounter5h = 0xC85,
    hpmcounter6h = 0xC86,
    hpmcounter7h = 0xC87,
    hpmcounter8h = 0xC88,
    hpmcounter9h = 0xC89,
    hpmcounter10h = 0xC8A,
    hpmcounter11h = 0xC8B,
    hpmcounter12h = 0xC8C,
    hpmcounter13h = 0xC8D,
    hpmcounter14h = 0xC8E,
    hpmcounter15h = 0xC8F,
    hpmcounter16h = 0xC90,
    hpmcounter17h = 0xC91,
    hpmcounter18h = 0xC92,
    hpmcounter19h = 0xC93,
    hpmcounter20h = 0xC94,
    hpmcounter21h = 0xC95,
    hpmcounter22h = 0xC96,
    hpmcounter23h = 0xC97,
    hpmcounter24h = 0xC98,
    hpmcounter25h = 0xC99,
    hpmcounter26h = 0xC9A,
    hpmcounter27h = 0xC9B,
    hpmcounter28h = 0xC9C,
    hpmcounter29h = 0xC9D,
    hpmcounter30h = 0xC9E,
    hpmcounter31h = 0xC9F,

    // supervisor trap setup
    sstatus = 0x100,
    sie = 0x104,
    stvec = 0x105,
    scounteren = 0x106,

    // supervisor configuration
    senvcfg = 0x10A,

    // supervisor counter setup
    scountinhibit = 0x120,

    // supervisor trap handling
    sscratch = 0x140,
    sepc = 0x141,
    scause = 0x142,
    stval = 0x143,
    sip = 0x144,
    scountovf = 0xDA0,

    // supervisor protection and translation
    satp = 0x180,

    // debug/trace registers
    scontext = 0x5A8,

    // supervisor state enable registers
    sstateen0 = 0x10C,
    sstateen1 = 0x10D,
    sstateen2 = 0x10E,
    sstateen3 = 0x10F,

    // hypervisor trap setup
    hstatus = 0x600,
    hedeleg = 0x602,
    hideleg = 0x603,
    hie = 0x604,
    hcounteren = 0x606,
    hgeie = 0x607,
    hedelegh = 0x612,

    // hypervisor trap handling
    htval = 0x643,
    hip = 0x644,
    hvip = 0x645,
    htinst = 0x64A,
    hgeip = 0xE12,

    // hypervisor configuration
    henvcfg = 0x60A,
    henvcfgh = 0x61A,

    // hypervisor protection and translation
    hgatp = 0x680,

    // debug/trace registers
    hcontext = 0x6A8,

    // hypervisor counter/timer virtualization registers
    htimedelta = 0x605,
    htimedeltah = 0x615,

    // hypverisor state enable registers
    hstateen0 = 0x60C,
    hstateen1 = 0x60D,
    hstateen2 = 0x60E,
    hstateen3 = 0x60F,
    hstateen0h = 0x61C,
    hstateen1h = 0x61D,
    hstateen2h = 0x61E,
    hstateen3h = 0x61F,

    // virtual supervisor registers
    vsstatus = 0x200,
    vsie = 0x204,
    vstvec = 0x205,
    vsscratch = 0x240,
    vsepc = 0x241,
    vscause = 0x242,
    vstval = 0x243,
    vsip = 0x244,
    vsatp = 0x280,

    // machine information registers
    mvendorid = 0xF11,
    marchid = 0xF12,
    mimpid = 0xF13,
    mhartid = 0xF14,
    mconfigptr = 0xF15,

    // machine trap setup
    mstatus = 0x300,
    misa = 0x301,
    medeleg = 0x302,
    mideleg = 0x303,
    mie = 0x304,
    mtvec = 0x305,
    mcounteren = 0x306,
    mstatush = 0x310,
    medelegh = 0x312,

    // machine trap handling
    mscratch = 0x340,
    mepc = 0x341,
    mcause = 0x342,
    mtval = 0x343,
    mip = 0x344,
    mtinst = 0x34A,
    mtval2 = 0x34B,

    // machine configuration
    menvcfg = 0x30A,
    menvcfgh = 0x31A,
    mseccfg = 0x747,
    mseccfgh = 0x757,

    // machine memory protection
    pmpcfg0 = 0x3A0,
    pmpcfg1 = 0x3A1,
    pmpcfg2 = 0x3A2,
    pmpcfg3 = 0x3A3,
    pmpcfg4 = 0x3A4,
    pmpcfg5 = 0x3A5,
    pmpcfg6 = 0x3A6,
    pmpcfg7 = 0x3A7,
    pmpcfg8 = 0x3A8,
    pmpcfg9 = 0x3A9,
    pmpcfg10 = 0x3AA,
    pmpcfg11 = 0x3AB,
    pmpcfg12 = 0x3AC,
    pmpcfg13 = 0x3AD,
    pmpcfg14 = 0x3AE,
    pmpcfg15 = 0x3AF,
    pmpaddr0 = 0x3B0,
    pmpaddr1 = 0x3B1,
    pmpaddr2 = 0x3B2,
    pmpaddr3 = 0x3B3,
    pmpaddr4 = 0x3B4,
    pmpaddr5 = 0x3B5,
    pmpaddr6 = 0x3B6,
    pmpaddr7 = 0x3B7,
    pmpaddr8 = 0x3B8,
    pmpaddr9 = 0x3B9,
    pmpaddr10 = 0x3BA,
    pmpaddr11 = 0x3BB,
    pmpaddr12 = 0x3BC,
    pmpaddr13 = 0x3BD,
    pmpaddr14 = 0x3BE,
    pmpaddr15 = 0x3BF,
    pmpaddr16 = 0x3C0,
    pmpaddr17 = 0x3C1,
    pmpaddr18 = 0x3C2,
    pmpaddr19 = 0x3C3,
    pmpaddr20 = 0x3C4,
    pmpaddr21 = 0x3C5,
    pmpaddr22 = 0x3C6,
    pmpaddr23 = 0x3C7,
    pmpaddr24 = 0x3C8,
    pmpaddr25 = 0x3C9,
    pmpaddr26 = 0x3CA,
    pmpaddr27 = 0x3CB,
    pmpaddr28 = 0x3CC,
    pmpaddr29 = 0x3CD,
    pmpaddr30 = 0x3CE,
    pmpaddr31 = 0x3CF,
    pmpaddr32 = 0x3D0,
    pmpaddr33 = 0x3D1,
    pmpaddr34 = 0x3D2,
    pmpaddr35 = 0x3D3,
    pmpaddr36 = 0x3D4,
    pmpaddr37 = 0x3D5,
    pmpaddr38 = 0x3D6,
    pmpaddr39 = 0x3D7,
    pmpaddr40 = 0x3D8,
    pmpaddr41 = 0x3D9,
    pmpaddr42 = 0x3DA,
    pmpaddr43 = 0x3DB,
    pmpaddr44 = 0x3DC,
    pmpaddr45 = 0x3DD,
    pmpaddr46 = 0x3DE,
    pmpaddr47 = 0x3DF,
    pmpaddr48 = 0x3E0,
    pmpaddr49 = 0x3E1,
    pmpaddr50 = 0x3E2,
    pmpaddr51 = 0x3E3,
    pmpaddr52 = 0x3E4,
    pmpaddr53 = 0x3E5,
    pmpaddr54 = 0x3E6,
    pmpaddr55 = 0x3E7,
    pmpaddr56 = 0x3E8,
    pmpaddr57 = 0x3E9,
    pmpaddr58 = 0x3EA,
    pmpaddr59 = 0x3EB,
    pmpaddr60 = 0x3EC,
    pmpaddr61 = 0x3ED,
    pmpaddr62 = 0x3EE,
    pmpaddr63 = 0x3EF,

    // machine state enable registers
    mstateen0 = 0x30C,
    mstateen1 = 0x30D,
    mstateen2 = 0x30E,
    mstateen3 = 0x30F,
    mstateen0h = 0x31C,
    mstateen1h = 0x31D,
    mstateen2h = 0x31E,
    mstateen3h = 0x31F,

    // machine non maskable interrupt handling
    mnscratch = 0x740,
    mnepc = 0x741,
    mncause = 0x742,
    mnstatus = 0x744,

    // machine counter/timers
    mcycle = 0xB00,
    minsret = 0xB02,
    mhpmcounter3 = 0xB03,
    mhpmcounter4 = 0xB04,
    mhpmcounter5 = 0xB05,
    mhpmcounter6 = 0xB06,
    mhpmcounter7 = 0xB07,
    mhpmcounter8 = 0xB08,
    mhpmcounter9 = 0xB09,
    mhpmcounter10 = 0xB0A,
    mhpmcounter11 = 0xB0B,
    mhpmcounter12 = 0xB0C,
    mhpmcounter13 = 0xB0D,
    mhpmcounter14 = 0xB0E,
    mhpmcounter15 = 0xB0F,
    mhpmcounter16 = 0xB10,
    mhpmcounter17 = 0xB11,
    mhpmcounter18 = 0xB12,
    mhpmcounter19 = 0xB13,
    mhpmcounter20 = 0xB14,
    mhpmcounter21 = 0xB15,
    mhpmcounter22 = 0xB16,
    mhpmcounter23 = 0xB17,
    mhpmcounter24 = 0xB18,
    mhpmcounter25 = 0xB19,
    mhpmcounter26 = 0xB1A,
    mhpmcounter27 = 0xB1B,
    mhpmcounter28 = 0xB1C,
    mhpmcounter29 = 0xB1D,
    mhpmcounter30 = 0xB1E,
    mhpmcounter31 = 0xB1F,
    mcycleh = 0xB80,
    minsreth = 0xB82,
    mhpmcounter3h = 0xB83,
    mhpmcounter4h = 0xB84,
    mhpmcounter5h = 0xB85,
    mhpmcounter6h = 0xB86,
    mhpmcounter7h = 0xB87,
    mhpmcounter8h = 0xB88,
    mhpmcounter9h = 0xB89,
    mhpmcounter10h = 0xB8A,
    mhpmcounter11h = 0xB8B,
    mhpmcounter12h = 0xB8C,
    mhpmcounter13h = 0xB8D,
    mhpmcounter14h = 0xB8E,
    mhpmcounter15h = 0xB8F,
    mhpmcounter16h = 0xB90,
    mhpmcounter17h = 0xB91,
    mhpmcounter18h = 0xB92,
    mhpmcounter19h = 0xB93,
    mhpmcounter20h = 0xB94,
    mhpmcounter21h = 0xB95,
    mhpmcounter22h = 0xB96,
    mhpmcounter23h = 0xB97,
    mhpmcounter24h = 0xB98,
    mhpmcounter25h = 0xB99,
    mhpmcounter26h = 0xB9A,
    mhpmcounter27h = 0xB9B,
    mhpmcounter28h = 0xB9C,
    mhpmcounter29h = 0xB9D,
    mhpmcounter30h = 0xB9E,
    mhpmcounter31h = 0xB9F,

    // machine counter setup
    mcountinhibit = 0x320,
    mhpmevent3 = 0x323,
    mhpmevent4 = 0x324,
    mhpmevent5 = 0x325,
    mhpmevent6 = 0x326,
    mhpmevent7 = 0x327,
    mhpmevent8 = 0x328,
    mhpmevent9 = 0x329,
    mhpmevent10 = 0x32A,
    mhpmevent11 = 0x32B,
    mhpmevent12 = 0x32C,
    mhpmevent13 = 0x32D,
    mhpmevent14 = 0x32E,
    mhpmevent15 = 0x32F,
    mhpmevent16 = 0x330,
    mhpmevent17 = 0x331,
    mhpmevent18 = 0x332,
    mhpmevent19 = 0x333,
    mhpmevent20 = 0x334,
    mhpmevent21 = 0x335,
    mhpmevent22 = 0x336,
    mhpmevent23 = 0x337,
    mhpmevent24 = 0x338,
    mhpmevent25 = 0x339,
    mhpmevent26 = 0x33A,
    mhpmevent27 = 0x33B,
    mhpmevent28 = 0x33C,
    mhpmevent29 = 0x33D,
    mhpmevent30 = 0x33E,
    mhpmevent31 = 0x33F,
    mhpmevent3h = 0x723,
    mhpmevent4h = 0x724,
    mhpmevent5h = 0x725,
    mhpmevent6h = 0x726,
    mhpmevent7h = 0x727,
    mhpmevent8h = 0x728,
    mhpmevent9h = 0x729,
    mhpmevent10h = 0x72A,
    mhpmevent11h = 0x72B,
    mhpmevent12h = 0x72C,
    mhpmevent13h = 0x72D,
    mhpmevent14h = 0x72E,
    mhpmevent15h = 0x72F,
    mhpmevent16h = 0x730,
    mhpmevent17h = 0x731,
    mhpmevent18h = 0x732,
    mhpmevent19h = 0x733,
    mhpmevent20h = 0x734,
    mhpmevent21h = 0x735,
    mhpmevent22h = 0x736,
    mhpmevent23h = 0x737,
    mhpmevent24h = 0x738,
    mhpmevent25h = 0x739,
    mhpmevent26h = 0x73A,
    mhpmevent27h = 0x73B,
    mhpmevent28h = 0x73C,
    mhpmevent29h = 0x73D,
    mhpmevent30h = 0x73E,
    mhpmevent31h = 0x73F,

    // debug/trace registers
    tselect = 0x7A0,
    tdata1 = 0x7A1,
    tdata2 = 0x7A2,
    tdata3 = 0x7A3,
    mcontext = 0x7A8,

    // debug mode registers
    dcsr = 0x7B0,
    dpc = 0x7B1,
    dscratch0 = 0x7B2,
    dscratch1 = 0x7B3,

    const Self = @This();

    pub inline fn read(self: Self) u64 {
        var res: u64 = undefined;
        const inst = std.fmt.comptimePrint("csrr %[reg], {}", .{@intFromEnum(self)});
        asm volatile (inst
            : [reg] "=r" (res),
        );

        return res;
    }

    pub inline fn write(self: Self, val: u64) void {
        const inst = std.fmt.comptimePrint("csrw {}, %[reg]", .{@intFromEnum(self)});
        asm volatile (inst
            :
            : [reg] "r" (val),
        );
    }

    pub inline fn setBits(self: Self, mask: u64) void {
        const inst = std.fmt.comptimePrint("csrs {}, %[reg]", .{@intFromEnum(self)});
        asm volatile (inst
            :
            : [reg] "r" (mask),
        );
    }

    pub inline fn clearBits(self: Self, mask: u64) void {
        const inst = std.fmt.comptimePrint("csrc {}, %[reg]", .{@intFromEnum(self)});
        asm volatile (inst
            :
            : [reg] "r" (mask),
        );
    }

    pub inline fn readAndSetBits(self: Self, mask: u64) u64 {
        var res: u64 = undefined;
        const inst = std.fmt.comptimePrint("csrrs %[outreg], {}, %[inreg]", .{@intFromEnum(self)});
        asm volatile (inst
            : [outreg] "=r" (res),
            : [inreg] "r" (mask),
        );
    }

    pub inline fn readAndWrite(self: Self, val: u64) u64 {
        var res: u64 = undefined;
        const inst = std.fmt.comptimePrint("csrrw %[outreg], {}, %[inreg]", .{@intFromEnum(self)});
        asm volatile (inst
            : [outreg] "=r" (res),
            : [inreg] "r" (val),
        );
    }

    pub inline fn readAndClearBits(self: Self, mask: u64) u64 {
        var res: u64 = undefined;
        const inst = std.fmt.comptimePrint("csrrc %[outreg], {}, %[inreg]", .{@intFromEnum(self)});
        asm volatile (inst
            : [outreg] "=r" (res),
            : [inreg] "r" (mask),
        );
    }
};
