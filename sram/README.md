# Virtua Racing (USA): battery-saved records

`Virtua Racing (U) [SRAM].bin` is Virtua Racing (USA) patched to keep its
records in battery-backed SRAM, so the course rankings, fastest laps and
best-lap times survive switching off.

- Input ROM: `Virtua Racing (U).bin`, 2 MB, CRC32 `7E1A324A`
- Output ROM: CRC32 `2D7EFF2F`, header checksum `$7174`

## What gets saved

The game keeps these in 68000 RAM and reloads its built-in defaults at every
power-on (the Reset button already keeps them):

| RAM | What |
| --- | --- |
| `$FFFA08-$FFFC47` | Course rankings: 3 courses x 24 entries x 8 bytes (name, view, BCD time) |
| `$FFFC48-$FFFC5F` | Fastest lap per course, same format |
| `$FFFDCA-$FFFDED` | Best-lap reference per course (Free Run "best lap" and split times) |

## How the patch works

- **Header**: `$1B0` now says `RA $F8 $20`, `$200001-$203FFF`: 8 KB battery
  SRAM on odd bytes, the standard layout emulators and flash carts read. The
  SVP chip only decodes `$300000` and up, so `$200000` is free.
- **Boot** (`$020296`): after the game copies its default records, the patch
  loads the saved ones. Blank or corrupt SRAM gets the defaults written to it.
- **Name entry done** (`$02DC9E`): saves after a new ranking or fastest lap
  is entered.
- **New best lap** (`$02B5E0`, `$02B7E2`): saves when a lap beats the
  course's best-lap reference.
- The data is stored twice, each copy with a magic word (`VRS1`) and a
  checksum, so switching off in the middle of a save loses at most the newest
  record.
- The new code (300 bytes) sits in empty space at `$1FC000`.

## Testing

Genesis Plus GX (libretro), driven headless from a script:

1. Booted with blank SRAM. Both save slots were written with the game's
   defaults.
2. Edited the save by hand (rank 1 `ALX 2'59"99`, fastest lap `ZZZ`), then
   booted again. The Records screen showed the edited entries.
3. Corrupted the first copy. The game loaded the second one and repaired the
   first. With both copies corrupted, it fell back to the defaults.
4. An autopilot drove Free Run on Big Forest. Lap 1 (1'22"06) beat the
   reference, the save was written, and after a power cycle Free Run showed
   1'22"06 as the best lap.
5. The autopilot finished a Virtua Racing race, with the race timer held so
   the bot didn't run out of time. Name entry stored the result. After a
   power cycle the Records screen listed it in 1st place (7'28"25) along
   with the fastest lap (1'14"53).

PicoDrive (libretro): a blank SRAM was formatted with both copies valid, and
the save from step 5 loaded into RAM at boot. That covers the same read and
write routines.

## Compatibility notes

- Emulators that read the SRAM header and support the SVP: Genesis Plus GX
  and PicoDrive (both tested), Kega Fusion, Ares and MAME should all
  work. BlastEm doesn't emulate the SVP, so it can't run Virtua Racing at all.
- MiSTer: the stock MegaDrive core turns SRAM saving off for SVP carts, so
  records only save with the TREX fork of the core (tested working with
  TREX core v3).
- Flash carts: this only works on a cart that runs SVP games, such as the
  Mega EverDrive PRO, and that cart also has to give SVP games SRAM. Not
  tested here.
- An original cartridge has no SRAM or battery, so on real hardware the
  patch needs a flash cart or a modified board.

## Building

Needs GNU binutils for m68k (`binutils-m68k-linux-gnu`) and Python 3:

```sh
sh build.sh "Virtua Racing (U).bin"
```

`build.sh` assembles `vr_sram.asm` with `m68k-linux-gnu-as -M`, links it at
`$1FC000`, and runs `patch.py`. `patch.py` checks the input ROM's CRC and the
original bytes at every hook before patching, then fixes the header checksum.
