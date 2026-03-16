@echo off
REM Build script for C benchmarks
REM Usage: build.bat

set CC=riscv-none-elf-gcc
set OBJCOPY=riscv-none-elf-objcopy
set OBJDUMP=riscv-none-elf-objdump
set CFLAGS=-march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -O2 -ffreestanding -fno-builtin
set LDFLAGS=-T link.ld -Wl,--no-relax

echo ============================================
echo  Building C Benchmarks for Morphable CPU
echo ============================================

echo.
echo --- bench_matmul ---
%CC% %CFLAGS% %LDFLAGS% -o bench_matmul.elf start.S bench_matmul.c
%OBJCOPY% -O binary bench_matmul.elf bench_matmul.bin
%OBJDUMP% -d bench_matmul.elf > bench_matmul.dis
python elf2hex.py bench_matmul.bin bench_matmul.hex

echo.
echo --- bench_crc ---
%CC% %CFLAGS% %LDFLAGS% -o bench_crc.elf start.S bench_crc.c
%OBJCOPY% -O binary bench_crc.elf bench_crc.bin
%OBJDUMP% -d bench_crc.elf > bench_crc.dis
python elf2hex.py bench_crc.bin bench_crc.hex

echo.
echo --- bench_qsort ---
%CC% %CFLAGS% %LDFLAGS% -o bench_qsort.elf start.S bench_qsort.c
%OBJCOPY% -O binary bench_qsort.elf bench_qsort.bin
%OBJDUMP% -d bench_qsort.elf > bench_qsort.dis
python elf2hex.py bench_qsort.bin bench_qsort.hex

echo.
echo --- bench_bsearch ---
%CC% %CFLAGS% %LDFLAGS% -o bench_bsearch.elf start.S bench_bsearch.c
%OBJCOPY% -O binary bench_bsearch.elf bench_bsearch.bin
%OBJDUMP% -d bench_bsearch.elf > bench_bsearch.dis
python elf2hex.py bench_bsearch.bin bench_bsearch.hex

echo.
echo --- bench_string ---
%CC% %CFLAGS% %LDFLAGS% -o bench_string.elf start.S bench_string.c
%OBJCOPY% -O binary bench_string.elf bench_string.bin
%OBJDUMP% -d bench_string.elf > bench_string.dis
python elf2hex.py bench_string.bin bench_string.hex

echo.
echo --- bench_linkedlist ---
%CC% %CFLAGS% %LDFLAGS% -o bench_linkedlist.elf start.S bench_linkedlist.c
%OBJCOPY% -O binary bench_linkedlist.elf bench_linkedlist.bin
%OBJDUMP% -d bench_linkedlist.elf > bench_linkedlist.dis
python elf2hex.py bench_linkedlist.bin bench_linkedlist.hex

echo.
echo --- bench_fib_recursive ---
%CC% %CFLAGS% %LDFLAGS% -o bench_fib_recursive.elf start.S bench_fib_recursive.c
%OBJCOPY% -O binary bench_fib_recursive.elf bench_fib_recursive.bin
%OBJDUMP% -d bench_fib_recursive.elf > bench_fib_recursive.dis
python elf2hex.py bench_fib_recursive.bin bench_fib_recursive.hex

echo.
echo --- bench_dhrystone ---
%CC% %CFLAGS% %LDFLAGS% -o bench_dhrystone.elf start.S bench_dhrystone.c
%OBJCOPY% -O binary bench_dhrystone.elf bench_dhrystone.bin
%OBJDUMP% -d bench_dhrystone.elf > bench_dhrystone.dis
python elf2hex.py bench_dhrystone.bin bench_dhrystone.hex

echo.
echo ============================================
echo  Done! Check for .hex files:
echo ============================================
dir /b *.hex
echo.
pause