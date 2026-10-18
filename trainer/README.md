# Virtua Racing (USA): +6 trainer

`Virtua Racing (U) [SRAM] [T+6].bin` is the SRAM-saving Virtua Racing ROM
from `../sram/` with the Y/N trainer menu from
a generic Mega Drive trainer menu in front of it. Records still save to battery SRAM.

- Input ROM: `Virtua Racing (U) [SRAM].bin`, CRC32 `2D7EFF2F`
- Output ROM: CRC32 `BB24CE3F`, header checksum `$F55D`

![menu](screenshots/menu.png)

## The menu

The top line reads `VIRTUA RACING +6H BY TREX`, with a full-width row of dashes under it and another between the
cheats and the instructions, which are in cyan. It shows at power-on and on
Reset. Up/Down picks a cheat, Left/Right or any button (A, B, C, and X, Y,
Z on a 6-button pad) turns it on or off, and Start runs the game. Every
cheat starts off.

The menu font is "Invasion" by VileR, from the
[VGA text mode fonts](https://github.com/viler-int10h/vga-text-mode-fonts) collection.

| Cheat | What it does |
| --- | --- |
| INFINITE TIME | The race clock stops counting down. Checkpoints still add time, up to 99. |
| ALWAYS 1ST PLACE | You are always 1st in the race order, so you finish 1st. |
| ONE LAP RACE | The race ends after one lap. |
| TURBO | A stronger engine and a higher rev limit: about 390 km/h instead of 330. |
| NO GRASS SLOWDOWN | Wheels on grass or sand don't slow the car down. Walls and signs still stop you. |
| NO COLLISIONS | You drive straight through rival cars. |

The cheats change player 1's car, except the clock and lap count, which
belong to the whole race.

**About "all courses unlocked":** this cheat was on the original list, but
all three courses (Beginner, Medium, Expert) can already be picked from the
start in Virtua Racing, Free Run and 2 Players mode, so there is nothing to
unlock. TURBO is in its place.

## How it works

- **Reset vector** (`$000004`) points at the trainer. Start jumps to the
  game's own reset code at `$020000`.
- **Cheat switches** are 6 bytes at `$FF0F00`. The game never writes
  `$FF0000-$FF0FFF` after power-on (checked by logging every RAM write over
  boot, attract mode, all three game modes and a race). Its boot code only
  clears all RAM when the pad ports are uninitialised, and the menu has
  already set them up by then.
- **Hooks**: Virtua Racing works out the clock, race order, speed and so on
  from scratch every frame, so writing values into RAM wouldn't stick.
  Instead `patch.py` writes a `jsr` over a few game instructions for each
  cheat. With the cheat off, each hook does exactly what those instructions
  did.

| Address | Game code replaced | Hook |
| --- | --- | --- |
| `$02B2E4` | once-a-second clock tick | `Hook_Time`: skip `subq.w #1,$FFD054` |
| `$029E86` | checkpoint time bonus | `Hook_Bonus`: cap the clock at 99 |
| `$029C84` | race order sort key | `Hook_First`: player's key = `$7FFF` |
| `$02A1F2`, `$028956` | "laps in race" check (1P, 2P) | `Hook_Laps`: treat `$FFD310` as 1 |
| `$029544` | engine push on the car | `Hook_Turbo`: double it |
| `$029604` | engine speed before the rev limit | `Hook_Rpm`: 3/4 of it |
| `$02A2E4` | off-road drag (`$029A34`) | `Hook_Grass`: don't add it |
| `$02AE0C` | car-to-car collision check | `Hook_NoHit`: return at once |

- The new code (2,074 bytes) sits at `$1FC400`, after the SRAM patch.

## Testing

Genesis Plus GX (libretro), driven headless from a script, with an autopilot
that follows the line a rival car takes round Big Forest. Each cheat was
tested off and on from the same race start:

1. **Menu**: Left, Right, A, B, C, X, Y and Z each toggled the selected
   cheat (Genesis Plus GX and PicoDrive), and the presses set the six bytes at `$FF0F00`, and they were
   still set once the game was running.
2. **Infinite time**: off, the clock went 75, 72, 67 ... 57. On, it stayed
   at 75, rose with each checkpoint, and never went past 99.
3. **Always 1st**: off, the autopilot ran 7th to 9th. On, it was 1st every
   time it was checked.
4. **One lap race**: on, the race finished as lap 1 ended. Off, the race
   carried on.
5. **Turbo**: top speed went from 331 to 390 km/h, and 0-200 km/h took 496
   frames instead of 588.
6. **No grass slowdown**: with the car steered onto the grass at 324 km/h,
   it slowed to 264 km/h with the cheat off and held 324 with it on.
7. **No collisions**: the autopilot steered at rival cars. Off, it hit them
   twice (the game's hit flags were set and speed dropped). On, nothing hit
   and it drove through them.
8. **Everything on**: a Virtua Racing race finished in 1st after one lap.
   Name entry saved the time to SRAM.
9. Free Run and 2 Players mode both start and race with every cheat on.
   One lap race was only driven to the finish in Virtua Racing mode; the
   other two modes go through the same patched lap check (2 Players has
   its own copy, hooked at `$028956`).

PicoDrive (libretro): the menu works, and with everything on the race ran
in 1st at 384 km/h with the clock held and finished after one lap.

## Notes

- Records set with cheats on are saved like any other, so a one-lap race
  time can end up at the top of the rankings.
- After a one-lap race the result screen lists the lap in the 2nd slot.
  That's the game's own table, which expects 5 laps.
- Hardware and emulator support is the same as the SRAM ROM: an emulator or
  flash cart that runs SVP games (not BlastEm). On MiSTer, saving needs the
  TREX fork of the MegaDrive core.

## Building

Needs GNU binutils for m68k (`binutils-m68k-linux-gnu`) and Python 3:

```sh
sh build.sh "../sram/Virtua Racing (U) [SRAM].bin"
```

`build.sh` assembles `vr_trainer.asm` with `m68k-linux-gnu-as -M`, links it
at `$1FC400`, and runs `patch.py`. `patch.py` checks the input ROM's CRC and
the original bytes at every hook before patching, then fixes the header
checksum.
