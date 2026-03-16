/* Linker script for morphable CPU benchmarks */
/* Code starts at 0x0 (IMEM base) */
/* Data starts at 0x400 (1024 bytes into DMEM) */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 1K
    DMEM (rwx) : ORIGIN = 0x00000000, LENGTH = 1K
}

SECTIONS
{
    .text :
    {
        *(.text.init)
        *(.text)
        *(.text.*)
    } > IMEM

    .data :
    {
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
    } > DMEM

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
    } > DMEM
}
