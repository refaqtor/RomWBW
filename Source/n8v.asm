;======================================================================
;	N8 VDU DRIVER FOR N8VEM PROJECT
;
;	WRITTEN BY: DOUGLAS GOODALL
;	UPDATED BY: WAYNE WARTHEN -- 4/7/2013
;======================================================================
;
; TODO:
;   - IMPLEMENT CONSTANTS FOR SCREEN DIMENSIONS
;   - IMPLEMENT SET CURSOR STYLE (VDASCS) FUNCTION
;   - IMPLEMENT ALTERNATE DISPLAY MODES?
;   - IMPLEMENT DYNAMIC READ/WRITE OF CHARACTER BITMAP DATA?
;
;======================================================================
; N8V DRIVER - CONSTANTS
;======================================================================
;
N8V_CMDREG	.EQU	N8_BASE + $19	; READ STATUS / WRITE REG SEL
N8V_DATREG	.EQU	N8_BASE + $18	; READ/WRITE DATA
;
N8V_ROWS	.EQU	24
N8V_COLS	.EQU	40
;
;======================================================================
; N8V DRIVER - INITIALIZATION
;======================================================================
;
N8V_INIT:
	PRTS("N8V: IO=0x$")
	LD	A,N8V_DATREG
	CALL	PRTHEXBYTE
;
	CALL 	N8V_CRTINIT		; SETUP THE N8V CHIP REGISTERS
	CALL	N8V_LOADFONT		; LOAD FONT DATA FROM ROM TO N8V STRORAGE
;
N8V_RESET:
	LD	DE,0			; ROW = 0, COL = 0
	CALL	N8V_XY			; SEND CURSOR TO TOP LEFT
	LD	A,' '			; BLANK THE SCREEN
	LD	DE,N8V_ROWS * N8V_COLS	; FILL ENTIRE BUFFER
	CALL	N8V_FILL		; DO IT
	LD	DE,0			; ROW = 0, COL = 0
	CALL	N8V_XY			; SEND CURSOR TO TOP LEFT
	
	XOR	A			; SIGNAL SUCCESS
	RET
;	
;======================================================================
; N8V DRIVER - CHARACTER I/O (CIO) DISPATCHER AND FUNCTIONS
;======================================================================
;
N8V_DISPCIO:
	LD	A,B			; GET REQUESTED FUNCTION
	AND	$0F			; ISOLATE SUB-FUNCTION
	JR	Z,N8V_CIOIN		; $00
	DEC	A
	JR	Z,N8V_CIOOUT		; $01
	DEC	A
	JR	Z,N8V_CIOIST		; $02
	DEC	A
	JR	Z,N8V_CIOOST		; $03
	CALL	PANIC
;	
N8V_CIOIN:
	JP	PPK_READ		; CHAIN TO KEYBOARD DRIVER
;
N8V_CIOIST:
	JP	PPK_STAT		; CHAIN TO KEYBOARD DRIVER
;
N8V_CIOOUT:
	JP	N8V_VDAWRC		; WRITE CHARACTER
;
N8V_CIOOST:
	XOR	A			; A = 0
	INC	A			; A = 1, SIGNAL OUTPUT BUFFER READY
	RET
;	
;======================================================================
; N8V DRIVER - VIDEO DISPLAY ADAPTER (VDA) DISPATCHER AND FUNCTIONS
;======================================================================
;
N8V_DISPVDA:
	LD	A,B		; GET REQUESTED FUNCTION
	AND	$0F		; ISOLATE SUB-FUNCTION

	JR	Z,N8V_VDAINI	; $40
	DEC	A
	JR	Z,N8V_VDAQRY	; $41
	DEC	A
	JR	Z,N8V_VDARES	; $42
	DEC	A
	JR	Z,N8V_VDASCS	; $43
	DEC	A
	JR	Z,N8V_VDASCP	; $44
	DEC	A
	JR	Z,N8V_VDASAT	; $45
	DEC	A
	JR	Z,N8V_VDASCO	; $46
	DEC	A
	JR	Z,N8V_VDAWRC	; $47
	DEC	A
	JR	Z,N8V_VDAFIL	; $48
	DEC	A
	JR	Z,N8V_VDACPY	; $49
	DEC	A
	JR	Z,N8V_VDASCR	; $4A
	DEC	A
	JP	Z,PPK_STAT	; $4B
	DEC	A
	JP	Z,PPK_FLUSH	; $4C
	DEC	A
	JP	Z,PPK_READ	; $4D
	CALL	PANIC

N8V_VDAINI:
	JP	N8V_INIT	; INITIALIZE

N8V_VDAQRY:
	LD	C,$00		; MODE ZERO IS ALL WE KNOW
	LD	D,N8V_ROWS	; ROWS
	LD	E,N8V_COLS	; COLS
	LD	HL,0		; EXTRACTION OF CURRENT BITMAP DATA NOT SUPPORTED YET
	XOR	A		; SIGNAL SUCCESS
	RET
	
N8V_VDARES:
	JR	N8V_RESET	; DO THE RESET
	
N8V_VDASCS:
	CALL	PANIC		; NOT IMPLEMENTED (YET)
	
N8V_VDASCP:
	CALL	N8V_XY		; SET CURSOR POSITION
	XOR	A		; SIGNAL SUCCESS
	RET
	
N8V_VDASAT:
	XOR	A		; NOT POSSIBLE, JUST SIGNAL SUCCESS
	RET
	
N8V_VDASCO:
	XOR	A		; NOT POSSIBLE, JUST SIGNAL SUCCESS
	RET
	
N8V_VDAWRC:
	LD	A,E		; CHARACTER TO WRITE GOES IN A
	CALL	N8V_PUTCHAR	; PUT IT ON THE SCREEN
	XOR	A		; SIGNAL SUCCESS
	RET
	
N8V_VDAFIL:
	LD	A,E		; FILL CHARACTER GOES IN A
	EX	DE,HL		; FILL LENGTH GOES IN DE
	CALL	N8V_FILL	; DO THE FILL
	XOR	A		; SIGNAL SUCCESS
	RET

N8V_VDACPY:
	; LENGTH IN HL, SOURCE ROW/COL IN DE, DEST IS N8V_POS
	; BLKCPY USES: HL=SOURCE, DE=DEST, BC=COUNT
	PUSH	HL		; SAVE LENGTH
	CALL	N8V_XY2IDX	; ROW/COL IN DE -> SOURCE ADR IN HL
	POP	BC		; RECOVER LENGTH IN BC
	LD	DE,(N8V_POS)	; PUT DEST IN DE
	JP	N8V_BLKCPY	; DO A BLOCK COPY
	
N8V_VDASCR:
	LD	A,E		; LOAD E INTO A
	OR	A		; SET FLAGS
	RET	Z		; IF ZERO, WE ARE DONE
	PUSH	DE		; SAVE E
	JP	M,N8V_VDASCR1	; E IS NEGATIVE, REVERSE SCROLL
	CALL	N8V_SCROLL	; SCROLL FORWARD ONE LINE
	POP	DE		; RECOVER E
	DEC	E		; DECREMENT IT
	JR	N8V_VDASCR	; LOOP
N8V_VDASCR1:
	CALL	N8V_RSCROLL	; SCROLL REVERSE ONE LINE
	POP	DE		; RECOVER E
	INC	E		; INCREMENT IT
	JR	N8V_VDASCR	; LOOP
;
;======================================================================
; N8V DRIVER - PRIVATE DRIVER FUNCTIONS
;======================================================================
;
;----------------------------------------------------------------------
; SET TMS9918 REGISTER VALUE
;   N8V_SET WRITES VALUE IN A TO VDU REGISTER SPECIFIED IN C
;----------------------------------------------------------------------
;
N8V_SET:
	OUT	(N8V_CMDREG),A		; WRITE IT
	NOP
	LD	A,C			; GET THE DESIRED REGISTER
	OR	$80			; SET BIT 7 
	OUT	(N8V_CMDREG),A		; SELECT THE DESIRED REGISTER
	NOP
	RET
;
;----------------------------------------------------------------------
; SET TMS9918 READ/WRITE ADDRESS
;   N8V_WR SETS TMS9918 TO BEGIN WRITING TO ADDRESS SPECIFIED IN HL
;   N8V_RD SETS TMS9918 TO BEGIN READING TO ADDRESS SPECIFIED IN HL
;----------------------------------------------------------------------
;
N8V_WR:
	PUSH	HL
	SET	6,H			; SET WRITE BIT
	CALL	N8V_RD
	POP	HL
	RET
;
N8V_RD:
	LD	A,L
	OUT	(N8V_CMDREG),A
	NOP
	LD	A,H
	OUT	(N8V_CMDREG),A
	NOP
	RET
;
;----------------------------------------------------------------------
; MOS 8563 DISPLAY CONTROLLER CHIP INITIALIZATION
;----------------------------------------------------------------------
;
N8V_CRTINIT:
	; SET WRITE ADDRESS TO $0
	LD	HL,0
	CALL	N8V_WR
;
	; FILL ENTIRE RAM CONTENTS
	LD	DE,$4000
N8V_CRTINIT1:
	XOR	A
	OUT	(N8V_DATREG),A
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,N8V_CRTINIT1
;
	; INITIALIZE VDU REGISTERS
    	LD 	C,0			; START WITH REGISTER 0
	LD	B,N8V_INIT9918LEN	; NUMBER OF REGISTERS TO INIT
    	LD 	HL,N8V_INIT9918		; HL = POINTER TO THE DEFAULT VALUES
N8V_CRTINIT2:
	LD	A,(HL)			; GET VALUE
	CALL	N8V_SET			; WRITE IT
	INC	HL			; POINT TO NEXT VALUE
	INC	C			; POINT TO NEXT REGISTER
	DJNZ	N8V_CRTINIT2		; LOOP
    	RET
;
;----------------------------------------------------------------------
; LOAD FONT DATA
;----------------------------------------------------------------------
;
N8V_LOADFONT:
	; SET WRITE ADDRESS TO $800
	LD	HL,$800
	CALL	N8V_WR
;
	; FILL $800 BYTES FROM FONTDATA
	LD	HL,N8V_FONTDATA
	LD	DE,$100 * 8
N8V_LOADFONT1:
	LD	B,8
N8V_LOADFONT2:
	LD	A,(HL)
	PUSH	AF
	INC	HL
	DJNZ	N8V_LOADFONT2
;
	LD	B,8
N8V_LOADFONT3:
	POP	AF
	OUT	(N8V_DATREG),A
	DEC	DE
	DJNZ	N8V_LOADFONT3
;
	LD	A,D
	OR	E
	JR	NZ,N8V_LOADFONT1
;
	RET
;
;----------------------------------------------------------------------
; SET CURSOR POSITION TO ROW IN D AND COLUMN IN E
;----------------------------------------------------------------------
;
N8V_XY:
	CALL	N8V_XY2IDX		; CONVERT ROW/COL TO BUF IDX
	LD	(N8V_POS),HL		; SAVE THE RESULT (DISPLAY POSITION)
	RET
;
;----------------------------------------------------------------------
; CONVERT XY COORDINATES IN DE INTO LINEAR INDEX IN HL
; D=ROW, E=COL
;----------------------------------------------------------------------
;
N8V_XY2IDX:
	LD	A,E			; SAVE COLUMN NUMBER IN A
	LD	H,D			; SET H TO ROW NUMBER
	LD	E,N8V_COLS		; SET E TO ROW LENGTH
	CALL	MULT8			; MULTIPLY TO GET ROW OFFSET
	LD	E,A			; GET COLUMN BACK
	ADD	HL,DE			; ADD IT IN
	RET				; RETURN
;
;----------------------------------------------------------------------
; WRITE VALUE IN A TO CURRENT VDU BUFFER POSTION, ADVANCE CURSOR
;----------------------------------------------------------------------
;
N8V_PUTCHAR:
	PUSH	AF			; SAVE CHARACTER
	LD	HL,(N8V_POS)		; LOAD CURRENT POSITION INTO HL
	CALL	N8V_WR			; SET THE WRITE ADDRESS
	POP	AF			; RECOVER CHARACTER TO WRITE
	OUT	(N8V_DATREG),A		; WRITE THE CHARACTER
	LD	HL,(N8V_POS)		; LOAD CURRENT POSITION INTO HL
	INC	HL
	LD	(N8V_POS),HL
	RET
;
;----------------------------------------------------------------------
; FILL AREA IN BUFFER WITH SPECIFIED CHARACTER AND CURRENT COLOR/ATTRIBUTE
; STARTING AT THE CURRENT FRAME BUFFER POSITION
;   A: FILL CHARACTER
;   DE: NUMBER OF CHARACTERS TO FILL
;----------------------------------------------------------------------
;
N8V_FILL:
	LD	C,A			; SAVE THE CHARACTER TO WRITE
	LD	HL,(N8V_POS)		; SET STARTING POSITION
	CALL	N8V_WR			; SET UP FOR WRITE
;
N8V_FILL1:
	LD	A,C			; RECOVER CHARACTER TO WRITE
	OUT	(N8V_DATREG),A
	NOP \ NOP
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,N8V_FILL1
;
	RET
;
;----------------------------------------------------------------------
; SCROLL ENTIRE SCREEN FORWARD BY ONE LINE (CURSOR POSITION UNCHANGED)
;----------------------------------------------------------------------
;
N8V_SCROLL:
	LD	HL,0			; SOURCE ADDRESS OF CHARACER BUFFER
	LD	C,N8V_ROWS - 1		; SET UP LOOP COUNTER FOR ROWS - 1
;
N8V_SCROLL0:	; READ LINE THAT IS ONE PAST CURRENT DESTINATION
	PUSH	HL			; SAVE CURRENT DESTINATION
	LD	DE,N8V_COLS
	ADD	HL,DE			; POINT TO NEXT ROW SOURCE
	CALL	N8V_RD			; SET UP TO READ
	LD	DE,N8V_BUF
	LD	B,N8V_COLS
N8V_SCROLL1:
	IN	A,(N8V_DATREG)
	NOP \ NOP
	LD	(DE),A
	INC	DE
	DJNZ	N8V_SCROLL1
	POP	HL			; RECOVER THE DESTINATION
;	
	; WRITE THE BUFFERED LINE TO CURRENT DESTINATION
	CALL	N8V_WR			; SET UP TO WRITE
	LD	DE,N8V_BUF
	LD	B,N8V_COLS
N8V_SCROLL2:
	LD	A,(DE)
	OUT	(N8V_DATREG),A
	NOP \ NOP
	INC	DE
	DJNZ	N8V_SCROLL2
;
	; BUMP TO NEXT LINE
	LD	DE,N8V_COLS
	ADD	HL,DE
	DEC	C			; DECREMENT ROW COUNTER
	JR	NZ,N8V_SCROLL0		; LOOP THRU ALL ROWS
;
	; FILL THE NEWLY EXPOSED BOTTOM LINE
	CALL	N8V_WR
	LD	A,' '
	LD	B,N8V_COLS
N8V_SCROLL3:
	OUT	(N8V_DATREG),A
	NOP \ NOP \ NOP \ NOP
	DJNZ	N8V_SCROLL3
;
	RET
;
;----------------------------------------------------------------------
; REVERSE SCROLL ENTIRE SCREEN BY ONE LINE (CURSOR POSITION UNCHANGED)
;----------------------------------------------------------------------
;
N8V_RSCROLL:
	LD	HL,N8V_COLS * (N8V_ROWS - 1)
	LD	C,N8V_ROWS - 1
;
N8V_RSCROLL0:	; READ THE LINE THAT IS ONE PRIOR TO CURRENT DESTINATION
	PUSH	HL			; SAVE THE DESTINATION ADDRESS
	LD	DE,-N8V_COLS
	ADD	HL,DE			; SET SOURCE ADDRESS
	CALL	N8V_RD			; SET UP TO READ
	LD	DE,N8V_BUF		; POINT TO BUFFER
	LD	B,N8V_COLS		; LOOP FOR EACH COLUMN
N8V_RSCROLL1:
	IN	A,(N8V_DATREG)		; GET THE CHAR
	NOP \ NOP			; RECOVER
	LD	(DE),A			; SAVE IN BUFFER
	INC	DE			; BUMP BUFFER POINTER
	DJNZ	N8V_RSCROLL1		; LOOP THRU ALL COLS
	POP	HL			; RECOVER THE DESTINATION ADDRESS
;
	; WRITE THE BUFFERED LINE TO CURRENT DESTINATION
	CALL	N8V_WR			; SET THE WRITE ADDRESS
	LD	DE,N8V_BUF		; POINT TO BUFFER
	LD	B,N8V_COLS		; INIT LOOP COUNTER
N8V_RSCROLL2:
	LD	A,(DE)			; LOAD THE CHAR
	OUT	(N8V_DATREG),A		; WRITE TO SCREEN
	NOP \ NOP			; DELAY
	INC	DE			; BUMP BUF POINTER
	DJNZ	N8V_RSCROLL2		; LOOP THRU ALL COLS
;
	; BUMP TO THE PRIOR LINE
	LD	DE,-N8V_COLS		; LOAD COLS (NEGATIVE)
	ADD	HL,DE			; BACK UP THE ADDRESS
	DEC	C			; DECREMENT ROW COUNTER
	JR	NZ,N8V_RSCROLL0		; LOOP THRU ALL ROWS
;
	; FILL THE NEWLY EXPOSED BOTTOM LINE
	CALL	N8V_WR
	LD	A,' '
	LD	B,N8V_COLS
N8V_RSCROLL3:
	OUT	(N8V_DATREG),A
	NOP \ NOP \ NOP \ NOP
	DJNZ	N8V_RSCROLL3
;
	RET
;
;----------------------------------------------------------------------
; BLOCK COPY BC BYTES FROM HL TO DE
;----------------------------------------------------------------------
;
N8V_BLKCPY:
	; SAVE DESTINATION AND LENGTH
	PUSH	BC		; LENGTH
	PUSH	DE		; DEST
;
	; READ FROM THE SOURCE LOCATION
N8V_BLKCPY1:
	CALL	N8V_RD		; SET UP TO READ FROM ADDRESS IN HL
	LD	DE,N8V_BUF	; POINT TO BUFFER
	LD	B,C
N8V_BLKCPY2:
	IN	A,(N8V_DATREG)	; GET THE NEXT BYTE
	NOP \ NOP		; DELAY
	LD	(DE),A		; SAVE IN BUFFER
	INC	DE		; BUMP BUF PTR
	DJNZ	N8V_BLKCPY2	; LOOP AS NEEDED
;
	; WRITE TO THE DESTINATION LOCATION
	POP	HL		; RECOVER DESTINATION INTO HL
	CALL	N8V_WR		; SET UP TO WRITE
	LD	DE,N8V_BUF	; POINT TO BUFFER
	POP	BC		; GET LOOP COUNTER BACK
	LD	B,C
N8V_BLKCPY3:
	LD	A,(DE)		; GET THE CHAR FROM BUFFER
	OUT	(N8V_DATREG),A	; WRITE TO VDU
	NOP \ NOP		; DELAY
	INC	DE		; BUMP BUF PTR
	DJNZ	N8V_BLKCPY3	; LOOP AS NEEDED
;
	RET
;
;==================================================================================================
;   N8V DRIVER - DATA
;==================================================================================================
;
N8V_POS		.DW 	0	; CURRENT DISPLAY POSITION
N8V_BUF		.FILL	256,0		; COPY BUFFER
;
;==================================================================================================
;   N8V DRIVER - TMS9918 REGISTER INITIALIZATION
;==================================================================================================
;
; Control Registers (write CMDREG):
;
; Reg	Bit 7	Bit 6	Bit 5	Bit 4	Bit 3	Bit 2	Bit 1	Bit 0	Description
; 0	-	-	-	-	-	-	M2	EXTVID
; 1	4/16K	BL	GINT	M1	M3	-	SI	MAG
; 2	-	-	-	-	PN13	PN12	PN11	PN10
; 3	CT13	CT12	CT11	CT10	CT9	CT8	CT7	CT6
; 4	-	-	-	-	-	PG13	PG12	PG11
; 5	-	SA13	SA12	SA11	SA10	SA9	SA8	SA7
; 6	-	-	-	-	-	SG13	SG12	SG11
; 7	TC3	TC2	TC1	TC0	BD3	BD2	BD1	BD0
;
; Status (read CMDREG):
;
; 	Bit 7	Bit 6	Bit 5	Bit 4	Bit 3	Bit 2	Bit 1	Bit 0	Description
; 	INT	5S	C	FS4	FS3	FS2	FS1	FS0
;
; M1,M2,M3	Select screen mode
; EXTVID	Enables external video input.
; 4/16K		Selects 16kB RAM if set. No effect in MSX1 system.
; BL		Blank screen if reset; just backdrop. Sprite system inactive
; SI		16x16 sprites if set; 8x8 if reset
; MAG		Sprites enlarged if set (sprite pixels are 2x2)
; GINT		Generate interrupts if set
; PN*		Address for pattern name table
; CT*		Address for colour table (special meaning in M2)
; PG*		Address for pattern generator table (special meaning in M2)
; SA*		Address for sprite attribute table
; SG*		Address for sprite generator table
; TC*		Text colour (foreground)
; BD*		Back drop (background). Sets the colour of the border around
; 		the drawable area. If it is 0, it is black (like colour 1).
; FS*		Fifth sprite (first sprite that's not displayed). Only valid
; 		if 5S is set.
; C		Sprite collision detected
; 5S		Fifth sprite (not displayed) detected. Value in FS* is valid.
; INT		Set at each screen update, used for interrupts.
;
N8V_INIT9918:
	.DB	$00		; REG 0 - NO EXTERNAL VID
	.DB	$50		; REG 1 - ENABLE SCREEN, SET MODE 1
	.DB	$00		; REG 2 - PATTERN NAME TABLE := 0
	.DB	$00		; REG 3 - NO COLOR TABLE
	.DB	$01		; REG 4 - SET PATTERN GENERATOR TABLE TO $800
	.DB	$00		; REG 5 - SPRITE ATTRIBUTE IRRELEVANT
	.DB	$00		; REG 6 - NO SPRITE GENERATOR TABLE
	.DB	$F0		; REG 7 - WHITE ON BLACK
;
N8V_INIT9918LEN	.EQU	$ - N8V_INIT9918
;
;==================================================================================================
;   N8V DRIVER - FONT DATA
;==================================================================================================
;
N8V_FONTDATA:
#INCLUDE "n8v_font.inc"