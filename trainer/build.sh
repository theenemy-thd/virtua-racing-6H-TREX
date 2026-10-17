#!/bin/sh
# Build the Virtua Racing trainer with GNU binutils (m68k) and apply it to the
# SRAM-saving ROM from ../sram/.
# usage: sh build.sh "Virtua Racing (U) [SRAM].bin"
set -e
ROM="${1:-../sram/Virtua Racing (U) [SRAM].bin}"
m68k-linux-gnu-as -M -m68000 -o vr_trainer.o vr_trainer.asm
m68k-linux-gnu-ld -Ttext=0x1FC400 -e 0x1FC400 -o vr_trainer.elf vr_trainer.o
m68k-linux-gnu-objcopy -O binary vr_trainer.elf vr_trainer.bin
m68k-linux-gnu-nm vr_trainer.elf > vr_trainer.bin.sym
python3 patch.py "$ROM" vr_trainer.bin "Virtua Racing (U) [SRAM] [T+6].bin"
rm -f vr_trainer.o vr_trainer.elf
