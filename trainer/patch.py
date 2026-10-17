"""Apply the +6 trainer to the SRAM-saving Virtua Racing (USA) ROM.

usage: python3 patch.py "Virtua Racing (U) [SRAM].bin" vr_trainer.bin "Virtua Racing (U) [SRAM] [T+6].bin"
vr_trainer.bin is vr_trainer.asm assembled and linked at $1FC400 (see build.sh).
"""
import sys, zlib

SRAM_CRC = 0x2D7EFF2F
BASE = 0x1FC400

src, blob_path, dst = sys.argv[1:4]
rom = bytearray(open(src, 'rb').read())
blob = open(blob_path, 'rb').read()
crc = zlib.crc32(rom) & 0xFFFFFFFF
if crc != SRAM_CRC:
    sys.exit('unexpected input ROM (CRC32 %08X, want %08X: the [SRAM] ROM)' % (crc, SRAM_CRC))

SYMS = {}
for line in open(blob_path + '.sym'):
    a, _, n = line.split()
    SYMS[n] = int(a, 16)

def put(addr, old, new):
    assert len(old) == len(new)
    assert rom[addr:addr + len(old)] == old, 'unexpected bytes at $%06X' % addr
    rom[addr:addr + len(new)] = new

def hook(addr, old_hex, name):
    old = bytes.fromhex(old_hex)
    new = b'\x4e\xb9' + SYMS[name].to_bytes(4, 'big')
    assert len(old) >= 6 and len(old) % 2 == 0
    put(addr, old, new + b'\x4e\x71' * ((len(old) - 6) // 2))

# trainer code into free space after the SRAM patch
assert BASE + len(blob) <= 0x200000
assert rom[BASE:BASE + len(blob)] == b'\xff' * len(blob)
rom[BASE:BASE + len(blob)] = blob

# reset vector: $020000 -> Trainer_Start (the trainer jumps to $020000)
put(0x000004, (0x020000).to_bytes(4, 'big'), SYMS['Trainer_Start'].to_bytes(4, 'big'))

hook(0x02B2E4, '4a38d30d 6604', 'Hook_Time')                        # tst.b $d30d.w / bne.b
hook(0x029E86, 'd178d054 4278d90c', 'Hook_Bonus')                    # checkpoint bonus
hook(0x029C84, '3029002c e148 d0690022', 'Hook_First')               # race order sort key
hook(0x02A1F2, '1038d310 5300', 'Hook_Laps')                        # laps in race - 1 (1 player)
hook(0x028956, '1038d310 5300', 'Hook_Laps')                        # same, 2 players
hook(0x029544, '6a02 d482 317c0100007a', 'Hook_Turbo')              # engine push
hook(0x029604, '4a83 6c02 7600', 'Hook_Rpm')                      # engine speed before the rev limit
hook(0x02A2E4, '4ebaf74e d1680016', 'Hook_Grass')                    # off-road drag
hook(0x02AE0C, '4a68006c 6638', 'Hook_NoHit')                       # car-to-car collision check

# header checksum
s = sum((rom[i] << 8) | rom[i + 1] for i in range(0x200, len(rom), 2)) & 0xFFFF
rom[0x18E:0x190] = s.to_bytes(2, 'big')
open(dst, 'wb').write(rom)
print('%s: %d bytes, checksum $%04X, CRC32 %08X' % (dst, len(rom), s, zlib.crc32(rom) & 0xFFFFFFFF))
