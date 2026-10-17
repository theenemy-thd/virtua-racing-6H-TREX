#!/bin/sh
# Build the Virtua Racing SRAM patch with GNU binutils (m68k) and apply it.
# usage: sh build.sh "Virtua Racing (U).bin"
set -e
ROM="${1:-Virtua Racing (U).bin}"
m68k-linux-gnu-as -M -m68000 -o vr_sram.o vr_sram.asm
m68k-linux-gnu-ld -Ttext=0x1FC000 -e 0x1FC000 -o vr_sram.elf vr_sram.o
m68k-linux-gnu-objcopy -O binary vr_sram.elf vr_sram.bin
m68k-linux-gnu-nm vr_sram.elf > vr_sram.bin.sym
python3 patch.py "$ROM" vr_sram.bin "Virtua Racing (U) [SRAM].bin"
rm -f vr_sram.o vr_sram.elf
