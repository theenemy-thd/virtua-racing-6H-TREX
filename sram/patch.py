"""Apply the SRAM patch to Virtua Racing (USA).

usage: python3 patch.py "Virtua Racing (U).bin" vr_sram.bin "Virtua Racing (U) [SRAM].bin"
vr_sram.bin is vr_sram.asm assembled and linked at $1FC000 (see build.sh).
"""
import sys, zlib

ORIG_CRC = 0x7E1A324A
BASE = 0x1FC000

src, blob_path, dst = sys.argv[1:4]
rom = bytearray(open(src, 'rb').read())
blob = open(blob_path, 'rb').read()
crc = zlib.crc32(rom) & 0xFFFFFFFF
if crc != ORIG_CRC:
    sys.exit('unexpected input ROM (CRC32 %08X, want %08X)' % (crc, ORIG_CRC))

def sym(name):
    # addresses from the linker map, filled in by build.sh via nm
    return SYMS[name]

SYMS = {}
for line in open(blob_path + '.sym'):
    a, _, n = line.split()
    SYMS[n] = int(a, 16)

def put(addr, old, new):
    assert len(old) == len(new)
    assert rom[addr:addr + len(old)] == old, 'unexpected bytes at $%06X' % addr
    rom[addr:addr + len(new)] = new

def jsr(target):
    return b'\x4e\xb9' + target.to_bytes(4, 'big')

NOP = b'\x4e\x71'

# code into free space at the end of the ROM
assert rom[BASE:BASE + len(blob)] == b'\xff' * len(blob)
rom[BASE:BASE + len(blob)] = blob

# cold boot: jsr $29294 (copy default records) -> jsr Hook_Boot
put(0x020296, jsr(0x029294), jsr(sym('Hook_Boot')))
# name entry done: st.b $FF2EAE.l -> jsr Hook_Name
put(0x02DC9E, bytes.fromhex('50f900ff2eae'), jsr(sym('Hook_Name')))
# new best-lap reference (two copies of the same code)
lap = bytes.fromhex('22c0 22f8d2b8 22b8d2bc')
put(0x02B5E0, lap, jsr(sym('Hook_Lap')) + NOP + NOP)
put(0x02B7E2, lap, jsr(sym('Hook_Lap')) + NOP + NOP)

# header: 8 KB battery-backed SRAM on odd bytes, $200001-$203FFF
put(0x1B0, b' ' * 12, b'RA\xf8\x20' + (0x200001).to_bytes(4, 'big') + (0x203FFF).to_bytes(4, 'big'))

# header checksum
s = sum((rom[i] << 8) | rom[i + 1] for i in range(0x200, len(rom), 2)) & 0xFFFF
rom[0x18E:0x190] = s.to_bytes(2, 'big')
open(dst, 'wb').write(rom)
print('%s: %d bytes, checksum $%04X, CRC32 %08X' % (dst, len(rom), s, zlib.crc32(rom) & 0xFFFFFFFF))
