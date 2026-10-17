; ===========================================================================
;  VIRTUA RACING (USA) - battery save for records
;  68000, Motorola syntax, GNU as in MRI mode (as -M). See build.sh.
;
;  The game keeps its records in 68000 RAM and loads them from ROM defaults
;  on every power-on (soft reset keeps them):
;    $FFFA08-$FFFC47  course rankings, 3 courses x 24 entries x 8 bytes
;                     (3-letter name, view mode, BCD time 00 0M SS hh)
;    $FFFC48-$FFFC5F  fastest lap per course, 3 x 8 bytes, same format
;    $FFFDCA-$FFFDED  best-lap reference per course used for the split
;                     display during a race, 3 x 12 bytes
;
;  This patch adds 8 KB of battery RAM at $200001-$203FFF (odd bytes, the
;  usual Mega Drive layout; the SVP chip only uses $300000 and up) and:
;    - at power-on, after the game copies its defaults, replaces them with
;      the saved records if a valid save exists, or writes the defaults to
;      a blank/corrupt SRAM so it becomes valid;
;    - after the name entry screen stores a new ranking/fastest lap, and
;      whenever a lap beats the best-lap reference, writes the records back.
;
;  The records are stored twice (slot A then slot B), each with a magic
;  word and checksum, so switching off in the middle of a save loses at
;  most the newest record.
; ===========================================================================

SRAM_A		equ	$200001		; slot A (odd bytes)
SRAM_B		equ	$200601		; slot B, $300 bytes of data further on
SRAM_CTRL	equ	$A130F1		; SRAM enable on carts that bank-switch

REC1		equ	$FFFA08		; rankings + fastest laps
REC1_LEN	equ	$258
REC2		equ	$FFFDCA		; best-lap references
REC2_LEN	equ	$24
SUM_SEED	equ	$5652		; 'VR', so an all-zero SRAM never passes

GAME_INIT	equ	$029294		; game routine: copy default records

; Linked at $1FC000 (free space at the end of the ROM), see build.sh.

; ---------------------------------------------------------------------------
; Hooks. patch.py points the game at these.
; ---------------------------------------------------------------------------

; $020296: jsr GAME_INIT.l  ->  jsr Hook_Boot.l   (cold boot only)
Hook_Boot:
	jsr	GAME_INIT
	movem.l	d0-d2/a0-a2,-(sp)
	move.b	#1,SRAM_CTRL
	lea	SRAM_A,a0
	bsr	Slot_Check
	beq	Hook_Boot_load
	lea	SRAM_B,a0
	bsr	Slot_Check
	bne	Hook_Boot_save		; nothing valid: store the defaults
	bsr	Slot_Load		; slot A was bad: load B, then repair A
	bra	Hook_Boot_save
Hook_Boot_load:
	bsr	Slot_Load
	bra	Hook_Boot_done
Hook_Boot_save:
	bsr	Save_Both
Hook_Boot_done:
	movem.l	(sp)+,d0-d2/a0-a2
	rts

; $02DC9E: st.b $FF2EAE.l  ->  jsr Hook_Name.l
; Runs once the name entry screen has written the name into the ranking
; and fastest lap tables.
Hook_Name:
	st.b	$FF2EAE
	bra	Save_Records

; $02B5E0 and $02B7E2: the three moves below  ->  jsr Hook_Lap.l / nop / nop
; Runs when a lap beats the course's best-lap reference.
Hook_Lap:
	move.l	d0,(a1)+
	move.l	$FFD2B8,(a1)+
	move.l	$FFD2BC,(a1)
	bra	Save_Records

; ---------------------------------------------------------------------------
; Save_Records: write the records to both slots. Keeps all registers.
; ---------------------------------------------------------------------------
Save_Records:
	movem.l	d0-d2/a0-a2,-(sp)
	move.b	#1,SRAM_CTRL
	bsr	Save_Both
	movem.l	(sp)+,d0-d2/a0-a2
	rts

Save_Both:
	lea	SRAM_A,a0
	bsr	Slot_Write
	lea	SRAM_B,a0
	; fall through

; a0 = slot. Trashes d0-d2/a0-a1.
Slot_Write:
	move.b	#0,(a0)			; invalidate the magic while writing
	addq.l	#2,a0
	lea	Magic+1(pc),a1
	moveq	#2,d0
Slot_Write_magic:
	move.b	(a1)+,(a0)
	addq.l	#2,a0
	dbra	d0,Slot_Write_magic
	move.w	#SUM_SEED,d1
	moveq	#0,d2
	lea	REC1,a1
	move.w	#REC1_LEN-1,d0
Slot_Write_rec1:
	move.b	(a1)+,d2
	move.b	d2,(a0)
	add.w	d2,d1
	addq.l	#2,a0
	dbra	d0,Slot_Write_rec1
	lea	REC2,a1
	moveq	#REC2_LEN-1,d0
Slot_Write_rec2:
	move.b	(a1)+,d2
	move.b	d2,(a0)
	add.w	d2,d1
	addq.l	#2,a0
	dbra	d0,Slot_Write_rec2
	move.b	d1,2(a0)
	lsr.w	#8,d1
	move.b	d1,(a0)
	move.b	Magic(pc),d0		; slot valid from here on
	suba.l	#(4+REC1_LEN+REC2_LEN)*2,a0
	move.b	d0,(a0)
	rts

; a0 = slot. Returns Z set if the slot holds a valid save. Keeps a0.
; Trashes d0-d2/a1-a2.
Slot_Check:
	movea.l	a0,a2
	lea	Magic(pc),a1
	moveq	#3,d0
Slot_Check_magic:
	move.b	(a1)+,d1
	cmp.b	(a2),d1
	bne	Slot_Check_bad
	addq.l	#2,a2
	dbra	d0,Slot_Check_magic
	move.w	#SUM_SEED,d1
	moveq	#0,d2
	move.w	#REC1_LEN+REC2_LEN-1,d0
Slot_Check_sum:
	move.b	(a2),d2
	add.w	d2,d1
	addq.l	#2,a2
	dbra	d0,Slot_Check_sum
	move.b	(a2),d2
	lsl.w	#8,d2
	move.b	2(a2),d2
	cmp.w	d2,d1
	rts
Slot_Check_bad:
	moveq	#1,d0			; clear Z
	rts

; a0 = valid slot. Copies it into the game's record tables.
Slot_Load:
	addq.l	#8,a0
	lea	REC1,a1
	move.w	#REC1_LEN-1,d0
Slot_Load_rec1:
	move.b	(a0),(a1)+
	addq.l	#2,a0
	dbra	d0,Slot_Load_rec1
	lea	REC2,a1
	moveq	#REC2_LEN-1,d0
Slot_Load_rec2:
	move.b	(a0),(a1)+
	addq.l	#2,a0
	dbra	d0,Slot_Load_rec2
	rts

Magic:
	dc.b	'VRS1'
	even
