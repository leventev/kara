ENTRY(start);
 
. = 0x80200000;

__stack_size = 0x10000;

SECTIONS {
	PROVIDE(__kernel_start = .);
	.text : ALIGN(4K) {
		PROVIDE(__text_start = .);
		*(.init);
		*(.text);
		*(.text*);
		PROVIDE(__text_end = .);
	}
	.rodata : ALIGN(4K) {
		PROVIDE(__rodata_start = .);
		*(.rodata);
		*(.rodata*);
		PROVIDE(__rodata_end = .);
	}
	PROVIDE(__global_pointer = .);
	.data : ALIGN(4K) {
		PROVIDE(__data_start = .);
		*(.data);
		*(.sdata);
		PROVIDE(__data_end = .);
	}
	.bss : ALIGN(4K) {
		PROVIDE(__bss_start = .);
		*(.bss);
		*(.bss*);
		*(.sbss);
		PROVIDE(__bss_end = .);
	}
	.stack(NOLOAD) : ALIGN(4K) {
		PROVIDE(__stack_start = .);
		. += __stack_size;
		PROVIDE(__stack_top = .);
		PROVIDE(__stack_end = .);
	}

	PROVIDE(__kernel_end = .);
}