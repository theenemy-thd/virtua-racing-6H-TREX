; ===========================================================================
;  VIRTUA RACING (USA) +6 TRAINER
;  68000, Motorola syntax, GNU as in MRI mode (as -M). See build.sh.
;
;  Built on the SRAM-saving ROM ("Virtua Racing (U) [SRAM].bin"), so records
;  still save. The Y/N menu is a generic Mega Drive trainer menu.
;
;  CONTROLS (menu)
;    Up / Down      move between cheats
;    Left / Right   turn the cheat ON/OFF
;    A, B, C (and X, Y, Z on a 6-button pad)  also turn it ON/OFF
;    Start          leave the menu and start the game
;
;  HOW IT WORKS
;    1. patch.py points the reset vector ($000004) at Trainer_Start, so the
;       menu runs first. Start jumps to the game's own reset code at $020000.
;    2. Each cheat is one byte at $FF0F00 (0 = off, 1 = on). The game never
;       touches $FF0000-$FF0FFF after power-on, and its boot code only clears
;       all RAM when the pad ports are still uninitialised, which the menu
;       has already done by then.
;    3. Virtua Racing works most values out every frame, so a RAM poke would
;       lose to the game. Each cheat is a jsr patched over the game's own
;       code instead (see the Hook_ routines). With the cheat off, a hook
;       does exactly what the instructions it replaced did.
;
;  Car data: 16 cars x $100 bytes from $FF9000, the player's car first.
;    $02 flags ($1000/$2000 = hit by another car), $06 speed, $16 drag,
;    $22 track segment, $28 race position, $2A laps done, $2C line crossings,
;    $2E/$32 x/z, $3A heading.
; ===========================================================================

; ---------------------------------------------------------------------------
; Hardware
; ---------------------------------------------------------------------------
VDP_DATA	equ	$C00000
VDP_CTRL	equ	$C00004
VERSION_REG	equ	$A10001
PAD1_DATA	equ	$A10003
PAD1_CTRL	equ	$A10009
TMSS_REG	equ	$A14000

PLANE_A		equ	$C000		; plane A name table in VRAM

PAL0		equ	$0000		; white text
PAL1		equ	$2000		; yellow text (selected row)
PAL2		equ	$4000		; green text (YES)
PAL3		equ	$6000		; red text (NO)
HELP		equ	PAL0+64		; cyan text: palette 0 colour 2 font (tiles 64+)

BTN_UP		equ	0
BTN_DOWN	equ	1
BTN_LEFT	equ	2
BTN_RIGHT	equ	3
BTN_B		equ	4
BTN_C		equ	5
BTN_A		equ	6
BTN_START	equ	7
BTN_Z		equ	8
BTN_Y		equ	9
BTN_X		equ	10
BTN_MODE	equ	11
TOGGLE_KEYS	equ	$077C		; left, right, A, B, C, X, Y, Z (not Mode)

; ---------------------------------------------------------------------------
; Trainer RAM
; ---------------------------------------------------------------------------
STACK_TOP	equ	$01000000	; same as the game's own initial SP
TRAINER_RAM	equ	$FF0F00

NUM_CHEATS	equ	6
Cheat_Flags	equ	TRAINER_RAM		; NUM_CHEATS bytes, 0=off 1=on
CHEAT_TIME	equ	Cheat_Flags+0
CHEAT_FIRST	equ	Cheat_Flags+1
CHEAT_ONELAP	equ	Cheat_Flags+2
CHEAT_TURBO	equ	Cheat_Flags+3
CHEAT_GRASS	equ	Cheat_Flags+4
CHEAT_NOCOLL	equ	Cheat_Flags+5
Menu_Cursor	equ	TRAINER_RAM+$10		; byte
Pad_Held	equ	TRAINER_RAM+$12		; word
Pad_Press	equ	TRAINER_RAM+$14		; word, newly pressed this frame

; ---------------------------------------------------------------------------
; Game addresses
; ---------------------------------------------------------------------------
GAME_ENTRY	equ	$020000		; game's original reset vector
PLAYER_CAR	equ	$9000		; .w address of car 0 (= $FF9000)
RACE_TIME	equ	$FFD054		; word, seconds left
RACE_LAPS	equ	$FFD310		; byte, laps in this race
GAME_OFFROAD	equ	$029A34		; game routine: off-road drag for car a0

; Linked at $1FC400 (free space after the SRAM patch), see build.sh.

; ===========================================================================
; Trainer entry (reset vector)
; ===========================================================================
Trainer_Start:
	move.w	#$2700,sr		; interrupts off
	move.l	#STACK_TOP,sp
	bsr	HW_Init
	lea	Cheat_Flags,a0		; all cheats off
	moveq	#NUM_CHEATS-1,d7
TS_Clear:
	clr.b	(a0)+
	dbra	d7,TS_Clear
	clr.w	Pad_Held

	bsr	ClearPlaneA
	clr.b	Menu_Cursor
	lea	MenuText(pc),a1		; draw the static text
TM_Text:
	move.w	(a1)+,d0		; x, or -1 at end of table
	bmi.s	TM_TextDone
	move.w	(a1)+,d1		; y
	move.w	(a1)+,d2		; attribute
	movea.l	(a1)+,a0		; string
	bsr	PrintAt
	bra.s	TM_Text
TM_TextDone:
	bsr	DrawOptions

TM_Loop:
	bsr	WaitVBlank
	bsr	ReadPad
	move.w	Pad_Press,d0
	beq.s	TM_Loop
	moveq	#0,d1
	move.b	Menu_Cursor,d1
	lea	Cheat_Flags,a0

	btst	#BTN_START,d0
	bne.s	TM_Exit
	btst	#BTN_UP,d0
	beq.s	TM_NotUp
	subq.b	#1,d1
	bpl.s	TM_SetCursor
	moveq	#NUM_CHEATS-1,d1	; wrap to bottom
	bra.s	TM_SetCursor
TM_NotUp:
	btst	#BTN_DOWN,d0
	beq.s	TM_NotDown
	addq.b	#1,d1
	cmpi.b	#NUM_CHEATS,d1
	blo.s	TM_SetCursor
	moveq	#0,d1			; wrap to top
TM_SetCursor:
	move.b	d1,Menu_Cursor
	bra.s	TM_Redraw
TM_NotDown:
	andi.w	#TOGGLE_KEYS,d0		; left, right or any button: flip
	beq.s	TM_Loop
	eori.b	#1,0(a0,d1.w)
TM_Redraw:
	bsr	DrawOptions
	bra.s	TM_Loop

TM_Exit:
	bsr	ClearPlaneA
TM_ExitWait:
	bsr	ReadPad			; wait for Start to be let go, or the
	tst.w	Pad_Held		; game's title screen would see it too
	bne.s	TM_ExitWait
	move.l	#STACK_TOP,sp
	jmp	GAME_ENTRY		; run the game

; ===========================================================================
; Cheat hooks. patch.py writes "jsr Hook_xxx" over the game code named in
; each comment (padded with nops) and checks the original bytes first.
; ===========================================================================

; INFINITE TIME
; $02B2E4: tst.b $d30d.w / bne.b $2b2ee  ->  jsr Hook_Time
; Runs once a second while the race clock is going.
; Returns to $02B2EA (subq.w #1,RACE_TIME), or skips it and returns to
; $02B2EE like the game's bne did.
Hook_Time:
	tst.b	CHEAT_TIME
	bne.s	HT_Hold
	tst.b	$FFD30D
	bne.s	HT_Skip
	rts
HT_Hold:
	cmpi.w	#99,RACE_TIME		; checkpoints still add time: keep it
	bls.s	HT_Skip			; within the 2-digit display
	move.w	#99,RACE_TIME
HT_Skip:
	addq.l	#4,(sp)			; skip the 4-byte subq
	rts

; $029E86: add.w d0,$d054.w / clr.w $d90c.w  ->  jsr Hook_Bonus / nop
; Adds the checkpoint bonus. With the cheat on the clock tops out at 99.
Hook_Bonus:
	add.w	d0,RACE_TIME
	clr.w	$FFD90C
	tst.b	CHEAT_TIME
	beq.s	HX_Done
	cmpi.w	#99,RACE_TIME
	bls.s	HX_Done
	move.w	#99,RACE_TIME
HX_Done:
	rts

; ALWAYS 1ST PLACE
; $029C84: move.w $2c(a1),d0 / lsl.w #8,d0 / add.w $22(a1),d0
;          ->  jsr Hook_First / nop / nop
; d0 is the player's sort key for the race order (laps*256 + segment). The
; highest key is 1st, so the cheat gives the player the highest key there is.
Hook_First:
	move.w	$2c(a1),d0
	lsl.w	#8,d0
	add.w	$22(a1),d0
	tst.b	CHEAT_FIRST
	beq.s	HF_Done
	move.w	#$7FFF,d0
HF_Done:
	rts

; ONE LAP RACE
; $02A1F2 (1 player) and $028956 (2 players):
;          move.b $d310.w,d0 / subq.b #1,d0  ->  jsr Hook_Laps
; The game finishes the race once laps done > d0. Free Run uses 0 here.
Hook_Laps:
	move.b	RACE_LAPS,d0
	tst.b	CHEAT_ONELAP
	beq.s	HL_Done
	cmpi.b	#1,d0
	bls.s	HL_Done
	moveq	#1,d0
HL_Done:
	subq.b	#1,d0
	rts

; TURBO
; $029544: bpl.b $29548 / add.l d2,d2 / move.w #$100,$7a(a0)
;          ->  jsr Hook_Turbo / nop / nop
; d2 is the push on the car this frame (engine minus drag). The game
; doubles it when it is negative; the cheat doubles it when it is positive
; too, for the player's car.
Hook_Turbo:
	tst.l	d2
	bpl.s	HB_Pos
	add.l	d2,d2
	bra.s	HB_Done
HB_Pos:
	tst.b	CHEAT_TURBO
	beq.s	HB_Done
	cmpa.w	#PLAYER_CAR,a0
	bne.s	HB_Done
	add.l	d2,d2
	cmpi.l	#$FFFE,d2		; the game multiplies d2/2 as a word next,
	ble.s	HB_Done			; so keep it in range
	move.l	#$FFFE,d2
HB_Done:
	move.w	#$100,$7a(a0)
	rts

; $029604: tst.l d3 / bge.b $2960a / moveq #0,d3  ->  jsr Hook_Rpm
; d3 is the engine speed worked out from the car's speed and gear, which
; the game then caps at the rev limit. Telling the engine it turns 3/4 as
; fast lets the car go a third faster before it reaches the limit.
Hook_Rpm:
	tst.l	d3
	bge.s	HR_Pos
	moveq	#0,d3
HR_Pos:
	tst.b	CHEAT_TURBO
	beq.s	HR_Done
	cmpa.w	#PLAYER_CAR,a0
	bne.s	HR_Done
	move.l	d3,-(sp)
	lsr.l	#2,d3
	neg.l	d3
	add.l	(sp)+,d3
HR_Done:
	rts

; NO GRASS SLOWDOWN
; $02A2E4: jsr $29a34(pc) / add.w d0,$16(a0)  ->  jsr Hook_Grass / nop
; $029A34 returns the extra drag from wheels that are off the tarmac.
Hook_Grass:
	jsr	GAME_OFFROAD
	tst.b	CHEAT_GRASS
	beq.s	HG_Add
	cmpa.w	#PLAYER_CAR,a0
	beq.s	HG_Done
HG_Add:
	add.w	d0,$16(a0)
HG_Done:
	rts

; NO COLLISIONS
; $02AE0C: tst.w $6c(a0) / bne.b $2ae4a  ->  jsr Hook_NoHit
; $02AE0C checks the player's car against the cars just ahead and behind.
; With the cheat on it returns at once, so rival cars are driven through.
Hook_NoHit:
	tst.b	CHEAT_NOCOLL
	beq.s	HN_Orig
	cmpa.w	#PLAYER_CAR,a0
	beq.s	HN_Exit
HN_Orig:
	tst.w	$6c(a0)
	bne.s	HN_Exit
	rts
HN_Exit:
	addq.l	#4,sp			; return from $02AE0C itself
	rts

; ===========================================================================
; Menu drawing
; ===========================================================================
MENU_X		equ	6
MENU_Y		equ	6
STATUS_X	equ	31

; Draw every cheat row: cursor, name, YES/NO
DrawOptions:
	movem.l	d0-d5/a0-a2,-(sp)
	moveq	#0,d4			; row index
	lea	CheatNames(pc),a1
	lea	Cheat_Flags,a2
DO_Row:
	move.w	d4,d1			; y = MENU_Y + row*2
	add.w	d1,d1
	addi.w	#MENU_Y,d1
	move.w	d4,d5
	add.w	d5,d5
	add.w	d5,d5			; d5 = row*4 for the pointer table

	cmp.b	Menu_Cursor,d4
	bne.s	DO_NotSel
	move.w	#PAL1,d2		; selected: yellow with arrow
	lea	StrCursor(pc),a0
	bra.s	DO_Name
DO_NotSel:
	move.w	#PAL0,d2		; not selected: white, no arrow
	lea	StrNoCursor(pc),a0
DO_Name:
	moveq	#MENU_X-2,d0
	bsr	PrintAt
	moveq	#MENU_X,d0
	movea.l	0(a1,d5.w),a0
	bsr	PrintAt

	moveq	#STATUS_X,d0
	tst.b	0(a2,d4.w)
	beq.s	DO_Off
	move.w	#PAL2,d2
	lea	StrYes(pc),a0
	bra.s	DO_Status
DO_Off:
	move.w	#PAL3,d2
	lea	StrNo(pc),a0
DO_Status:
	bsr	PrintAt

	addq.w	#1,d4
	cmpi.w	#NUM_CHEATS,d4
	blo.s	DO_Row
	movem.l	(sp)+,d0-d5/a0-a2
	rts

; Text helpers
; ===========================================================================

; Print a 0-terminated string on plane A
; in: a0 = string, d0.w = x, d1.w = y, d2.w = attribute (palette bits)
PrintAt:
	movem.l	d0-d3/a0,-(sp)
	lsl.w	#6,d1			; y * 64 cells per row
	add.w	d0,d1
	add.w	d1,d1			; 2 bytes per cell
	addi.w	#PLANE_A,d1
	move.w	d1,d0
	bsr	VDP_SetVRAMWrite
PA_Char:
	moveq	#0,d3
	move.b	(a0)+,d3
	beq.s	PA_Done
	subi.w	#32,d3			; font starts at tile 0 = space
	or.w	d2,d3
	move.w	d3,VDP_DATA
	bra.s	PA_Char
PA_Done:
	movem.l	(sp)+,d0-d3/a0
	rts

; Print a number 0-99 as two digits
; in: d3.b = value, d0.w = x, d1.w = y, d2.w = attribute
	rts

; Fill plane A with tile 0 (space)
ClearPlaneA:
	move.l	d0,-(sp)
	move.l	d7,-(sp)
	move.w	#PLANE_A,d0
	bsr	VDP_SetVRAMWrite
	moveq	#0,d0
	move.w	#(64*32/2)-1,d7
CP_Loop:
	move.l	d0,VDP_DATA
	dbra	d7,CP_Loop
	move.l	(sp)+,d7
	move.l	(sp)+,d0
	rts

; ===========================================================================
; Hardware helpers
; ===========================================================================

; Set the VDP to write VRAM at address d0.w
VDP_SetVRAMWrite:
	movem.l	d0-d1,-(sp)
	moveq	#0,d1
	move.w	d0,d1
	andi.w	#$3FFF,d0		; A13-A0 go in the top word
	swap	d0
	clr.w	d0
	rol.w	#2,d1			; A15-A14 go in bits 1-0
	andi.w	#3,d1
	move.w	d1,d0
	ori.l	#$40000000,d0		; VRAM write
	move.l	d0,VDP_CTRL
	movem.l	(sp)+,d0-d1
	rts

; Wait for the start of the next vertical blank (polling, no interrupts)
WaitVBlank:
	move.l	d0,-(sp)
WV_InBlank:
	move.w	VDP_CTRL,d0
	btst	#3,d0
	bne.s	WV_InBlank
WV_NotBlank:
	move.w	VDP_CTRL,d0
	btst	#3,d0
	beq.s	WV_NotBlank
	move.l	(sp)+,d0
	rts

; Read pad 1 (3 or 6 button). Call once per frame.
; out: Pad_Held, Pad_Press words, bits as BTN_xxx (1 = pressed)
ReadPad:
	movem.l	d0-d3/a0,-(sp)
	lea	PAD1_DATA,a0
	move.b	#$40,(a0)		; TH high
	nop
	nop
	move.b	(a0),d0			; ?1CBRLDU
	move.b	#$00,(a0)		; TH low
	nop
	nop
	move.b	(a0),d1			; ?0SA00DU
	move.b	#$40,(a0)
	nop
	nop
	move.b	#$00,(a0)
	nop
	nop
	move.b	#$40,(a0)
	nop
	nop
	move.b	#$00,(a0)
	nop
	nop
	move.b	(a0),d2			; low nibble 0000 on a 6-button pad
	move.b	#$40,(a0)
	nop
	nop
	move.b	(a0),d3			; ?1??MXYZ on a 6-button pad
	move.b	#$00,(a0)
	nop
	nop
	move.b	#$40,(a0)		; leave TH high

	andi.w	#$3F,d0			; CBRLDU
	andi.w	#$30,d1			; SA
	lsl.w	#2,d1
	or.w	d1,d0			; SACBRLDU (0 = pressed)
	andi.b	#$0F,d2
	bne.s	RP_3Button
	andi.w	#$0F,d3			; MXYZ
	lsl.w	#8,d3
	or.w	d3,d0
	bra.s	RP_Done
RP_3Button:
	ori.w	#$0F00,d0		; no 6-button pad: MXYZ released
RP_Done:
	not.w	d0
	andi.w	#$0FFF,d0		; 1 = pressed
	move.w	Pad_Held,d1
	move.w	d0,Pad_Held
	not.w	d1
	and.w	d1,d0			; pressed now and not last frame
	move.w	d0,Pad_Press
	movem.l	(sp)+,d0-d3/a0
	rts

; Set up TMSS, VDP, palette, font and pad port
HW_Init:
	move.b	VERSION_REG,d0		; TMSS: write 'SEGA' on newer consoles
	andi.b	#$0F,d0
	beq.s	HI_NoTMSS
	move.l	#$53454741,TMSS_REG
HI_NoTMSS:
	move.w	VDP_CTRL,d0		; clear any pending VDP command

	lea	VDPRegs(pc),a0
	moveq	#(VDPRegsEnd-VDPRegs)/2-1,d7
HI_Regs:
	move.w	(a0)+,VDP_CTRL
	dbra	d7,HI_Regs

	move.l	#$40000000,VDP_CTRL	; clear all 64KB of VRAM
	moveq	#0,d0
	move.w	#$4000-1,d7
HI_ClearVRAM:
	move.l	d0,VDP_DATA
	dbra	d7,HI_ClearVRAM

	move.l	#$40000010,VDP_CTRL	; clear vertical scroll
	moveq	#40-1,d7
HI_ClearVSRAM:
	move.w	d0,VDP_DATA
	dbra	d7,HI_ClearVSRAM

	move.l	#$C0000000,VDP_CTRL	; load palette
	lea	Palette(pc),a0
	moveq	#64-1,d7
HI_Palette:
	move.w	(a0)+,VDP_DATA
	dbra	d7,HI_Palette

	move.l	#$40000000,VDP_CTRL	; font to VRAM tile 0 in colour 1,
	moveq	#1,d5			; then again from tile 64 in colour 2
HI_FontCopy:
	lea	Font(pc),a0
	move.w	#FontEnd-Font-1,d7
HI_FontRow:
	move.b	(a0)+,d0		; 1 bit per pixel...
	moveq	#0,d1
	moveq	#8-1,d6
HI_FontPixel:
	lsl.l	#4,d1			; ...to 4 bits per pixel, colour d5
	add.b	d0,d0
	bcc.s	HI_FontBlank
	or.b	d5,d1
HI_FontBlank:
	dbra	d6,HI_FontPixel
	move.l	d1,VDP_DATA
	dbra	d7,HI_FontRow
	addq.b	#1,d5
	cmpi.b	#2,d5
	bls.s	HI_FontCopy

	move.b	#$40,PAD1_CTRL		; pad 1: TH is an output
	move.b	#$40,PAD1_DATA
	rts

; ===========================================================================

; VDP register setup
VDPRegs:
	dc.w	$8004			; 0: HBlank int off
	dc.w	$8164			; 1: display on, VBlank int on, mode 5
	dc.w	$8230			; 2: plane A at $C000
	dc.w	$8334			; 3: window at $D000
	dc.w	$8407			; 4: plane B at $E000
	dc.w	$857C			; 5: sprites at $F800
	dc.w	$8600
	dc.w	$8700			; 7: background = palette 0 colour 0
	dc.w	$8800
	dc.w	$8900
	dc.w	$8A00			; 10: HBlank counter
	dc.w	$8B00			; 11: full-screen scrolling
	dc.w	$8C81			; 12: 40 cells wide, no interlace
	dc.w	$8D3F			; 13: H scroll table at $FC00
	dc.w	$8E00
	dc.w	$8F02			; 15: auto-increment 2
	dc.w	$9001			; 16: planes 64x32 cells
	dc.w	$9100			; 17: window off
	dc.w	$9200			; 18: window off
VDPRegsEnd:

; Palettes: colour format 0000BBB0GGG0RRR0, colour 1 is the text colour
Palette:
	dc.w	$0400,$0EEE,$0EE0,$0000,$0000,$0000,$0000,$0000	; 0: white (1), cyan (2) on dark blue
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$00EE,$0000,$0000,$0000,$0000,$0000,$0000	; 1: yellow
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$00E0,$0000,$0000,$0000,$0000,$0000,$0000	; 2: green
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dc.w	$0000,$000E,$0000,$0000,$0000,$0000,$0000,$0000	; 3: red
	dc.w	$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000

; Static menu text: x, y, attribute, string pointer; x = -1 ends the table

; Static menu text: x, y, attribute, string pointer; x = -1 ends the table
MenuText:
	dc.w	7,2,PAL1
	dc.l	StrTitle
	dc.w	0,4,PAL0
	dc.l	StrSubtitle
	dc.w	0,18,PAL0
	dc.l	StrSubtitle
	dc.w	4,20,HELP
	dc.l	StrHelp1
	dc.w	4,22,HELP
	dc.l	StrHelp2
	dc.w	4,24,HELP
	dc.l	StrHelp3
	dc.w	-1

; One name per cheat, in Cheat_Flags order. Uppercase only: the font holds
; ASCII 32-95.
CheatNames:
	dc.l	StrCheat0
	dc.l	StrCheat1
	dc.l	StrCheat2
	dc.l	StrCheat3
	dc.l	StrCheat4
	dc.l	StrCheat5

StrCheat0:	dc.b	'INFINITE TIME',0
StrCheat1:	dc.b	'ALWAYS 1ST PLACE',0
StrCheat2:	dc.b	'ONE LAP RACE',0
StrCheat3:	dc.b	'TURBO',0
StrCheat4:	dc.b	'NO GRASS SLOWDOWN',0
StrCheat5:	dc.b	'NO COLLISIONS',0

StrTitle:	dc.b	'VIRTUA RACING +6H BY TREX',0
StrSubtitle:	dc.b	'----------------------------------------',0
StrHelp1:	dc.b	'UP/DOWN            CHOOSE A CHEAT',0
StrHelp2:	dc.b	'LEFT/RIGHT/BUTTONS CHEAT ON/OFF',0
StrHelp3:	dc.b	'START              PLAY THE GAME',0
StrCursor:	dc.b	'>',0
StrNoCursor:	dc.b	' ',0
StrYes:		dc.b	'YES',0
StrNo:		dc.b	'NO ',0
	even


; 8x8 font, 1 bit per pixel, ASCII 32-95 (expanded to 4bpp at boot)
; "Invasion" by VileR, from https://github.com/viler-int10h/vga-text-mode-fonts
Font:
	dc.b	$00,$00,$00,$00,$00,$00,$00,$00	; ' '
	dc.b	$38,$38,$38,$38,$38,$00,$38,$00	; '!'
	dc.b	$EE,$EE,$CC,$00,$00,$00,$00,$00	; '"'
	dc.b	$6C,$6C,$FE,$6C,$FE,$6C,$6C,$00	; '#'
	dc.b	$18,$7E,$E0,$FE,$06,$FC,$30,$00	; '$'
	dc.b	$00,$66,$BC,$78,$3C,$7A,$CC,$00	; '%'
	dc.b	$7C,$E6,$E4,$7F,$EC,$E6,$7F,$00	; '&'
	dc.b	$38,$38,$30,$00,$00,$00,$00,$00	; '''
	dc.b	$0C,$18,$30,$30,$38,$1C,$0C,$00	; '('
	dc.b	$30,$18,$0C,$0C,$1C,$38,$30,$00	; ')'
	dc.b	$10,$18,$FF,$7E,$3C,$7E,$C7,$00	; '*'
	dc.b	$00,$38,$38,$FE,$38,$38,$00,$00	; '+'
	dc.b	$00,$00,$00,$00,$00,$38,$38,$30	; ','
	dc.b	$00,$00,$00,$FE,$00,$00,$00,$00	; '-'
	dc.b	$00,$00,$00,$00,$00,$38,$38,$00	; '.'
	dc.b	$03,$06,$0C,$18,$30,$60,$C0,$00	; '/'
	dc.b	$7C,$FE,$E6,$EE,$F6,$E6,$7C,$00	; '0'
	dc.b	$1C,$7C,$1C,$1C,$1C,$1C,$1C,$00	; '1'
	dc.b	$7C,$FE,$E6,$06,$7C,$E0,$FE,$00	; '2'
	dc.b	$FC,$06,$7C,$06,$E6,$FE,$7C,$00	; '3'
	dc.b	$E0,$E0,$EC,$EC,$EC,$7E,$0C,$00	; '4'
	dc.b	$FE,$E0,$7C,$06,$E6,$FE,$7C,$00	; '5'
	dc.b	$7C,$E0,$FC,$E6,$E6,$FE,$7C,$00	; '6'
	dc.b	$FE,$FE,$E6,$0C,$18,$30,$70,$00	; '7'
	dc.b	$7C,$FE,$E6,$E6,$7C,$E6,$7C,$00	; '8'
	dc.b	$7C,$FE,$E6,$E6,$7E,$06,$7C,$00	; '9'
	dc.b	$00,$38,$38,$00,$00,$38,$38,$00	; ':'
	dc.b	$00,$38,$38,$00,$00,$38,$38,$30	; ';'
	dc.b	$00,$0E,$38,$E0,$38,$0E,$00,$00	; '<'
	dc.b	$00,$00,$7E,$00,$7E,$00,$00,$00	; '='
	dc.b	$00,$E0,$38,$0E,$38,$E0,$00,$00	; '>'
	dc.b	$FC,$FE,$E6,$0E,$1C,$00,$18,$00	; '?'
	dc.b	$7E,$FF,$EB,$EB,$EF,$E0,$7C,$00	; '@'
	dc.b	$7C,$06,$7E,$E6,$E6,$FE,$7E,$00	; 'A'
	dc.b	$FC,$FE,$E6,$E6,$FC,$E6,$FC,$00	; 'B'
	dc.b	$7C,$FE,$E6,$E0,$E0,$E6,$7C,$00	; 'C'
	dc.b	$F8,$FC,$EE,$E6,$E6,$E6,$FC,$00	; 'D'
	dc.b	$7C,$FE,$E6,$E6,$FE,$E0,$7C,$00	; 'E'
	dc.b	$7C,$FE,$E6,$E6,$E0,$FE,$E0,$00	; 'F'
	dc.b	$76,$FE,$EE,$E6,$7E,$06,$7C,$00	; 'G'
	dc.b	$E6,$E6,$E6,$E6,$FE,$E6,$E6,$00	; 'H'
	dc.b	$7C,$7C,$38,$38,$38,$38,$7C,$00	; 'I'
	dc.b	$7E,$7E,$06,$E6,$E6,$E6,$7C,$00	; 'J'
	dc.b	$E6,$E6,$E6,$EC,$F8,$EE,$E6,$00	; 'K'
	dc.b	$E0,$E0,$E0,$E0,$E6,$E6,$7C,$00	; 'L'
	dc.b	$C6,$EE,$FE,$D6,$E6,$E6,$E6,$00	; 'M'
	dc.b	$FC,$FE,$E6,$E6,$E6,$E6,$E6,$00	; 'N'
	dc.b	$7C,$FE,$E6,$E6,$E6,$E6,$7C,$00	; 'O'
	dc.b	$FC,$FE,$E6,$E6,$E6,$FC,$E0,$00	; 'P'
	dc.b	$7C,$FE,$E6,$E6,$E6,$EC,$7E,$03	; 'Q'
	dc.b	$FC,$FE,$E6,$EC,$F8,$EE,$E6,$00	; 'R'
	dc.b	$7C,$E0,$7C,$06,$E6,$FE,$7C,$00	; 'S'
	dc.b	$E0,$FE,$FE,$E0,$E6,$E6,$7C,$00	; 'T'
	dc.b	$E6,$E6,$E6,$E6,$E6,$E6,$7C,$00	; 'U'
	dc.b	$E6,$E6,$E6,$E6,$6C,$6C,$38,$00	; 'V'
	dc.b	$E6,$E6,$E6,$D6,$FE,$EE,$C6,$00	; 'W'
	dc.b	$E6,$E6,$E6,$E6,$7C,$E6,$E6,$00	; 'X'
	dc.b	$E6,$E6,$E6,$E6,$7E,$06,$7C,$00	; 'Y'
	dc.b	$FE,$FE,$E6,$06,$7C,$E0,$FE,$00	; 'Z'
	dc.b	$7C,$7C,$70,$70,$70,$70,$7C,$00	; '['
	dc.b	$C0,$60,$30,$18,$0C,$06,$03,$00	; '\'
	dc.b	$3E,$3E,$0E,$0E,$0E,$0E,$3E,$00	; ']'
	dc.b	$10,$38,$6C,$C6,$00,$00,$00,$00	; '^'
	dc.b	$00,$00,$00,$00,$00,$00,$00,$FF	; '_'
FontEnd:

	even
