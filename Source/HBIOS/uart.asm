;
;==================================================================================================
; UART DRIVER (SERIAL PORT)
;==================================================================================================
;
;  SETUP PARAMETER WORD:
;  +-------+---+-------------------+ +---+---+-----------+---+-------+
;  |       |RTS| ENCODED BAUD RATE | |DTR|XON|  PARITY   |STP| 8/7/6 |
;  +-------+---+---+---------------+ ----+---+-----------+---+-------+
;    F   E   D   C   B   A   9   8     7   6   5   4   3   2   1   0
;       -- MSB (D REGISTER) --           -- LSB (E REGISTER) --
;
;  UART CONFIGURATION REGISTERS:
;  +-------+---+-------------------+ +---+---+-----------+---+-------+
;  | 0   0 |AFE|LP  OT2 OT1 RTS DTR| |DLB|BRK|STK EPS PEN|STB|  WLS  |
;  +-------+---+-------------------+ +---+---+-----------+---+-------+
;    F   E   D   C   B   A   9   8     7   6   5   4   3   2   1   0
;              -- MCR --                        -- LCR --
;
;
UART_DEBUG		.EQU	FALSE
;
UART_NONE		.EQU	0	; UNKNOWN OR NOT PRESENT
UART_8250		.EQU	1
UART_16450		.EQU	2
UART_16550		.EQU	3
UART_16550A		.EQU	4
UART_16550C		.EQU	5
UART_16650		.EQU	6
UART_16750		.EQU	7
UART_16850		.EQU	8
;
UART_RBR		.EQU	0	; DLAB=0: RCVR BUFFER REG (READ)
UART_THR		.EQU	0	; DLAB=0: XMIT HOLDING REG (WRITE)
UART_IER		.EQU	1	; DLAB=0: INT ENABLE REG (READ)
UART_IIR		.EQU	2	; INT IDENT REGISTER (READ)
UART_FCR		.EQU	2	; FIFO CONTROL REG (WRITE)
UART_LCR		.EQU	3	; LINE CONTROL REG (READ/WRITE)
UART_MCR		.EQU	4	; MODEM CONTROL REG (READ/WRITE)
UART_LSR		.EQU	5	; LINE STATUS REG (READ)
UART_MSR		.EQU	6	; MODEM STATUS REG (READ)
UART_SCR		.EQU	7	; SCRATCH REGISTER (READ/WRITE)
UART_DLL		.EQU	0	; DLAB=1: DIVISOR LATCH (LS) (READ/WRITE)
UART_DLM		.EQU	1	; DLAB=1: DIVISOR LATCH (MS) (READ/WRITE)
UART_EFR		.EQU	2	; LCR=$BF: ENHANCED FEATURE REG (READ/WRITE)
;;
;UART_FIFO		.EQU	0	; FIFO ENABLE BIT
;UART_AFC		.EQU	1	; AUTO FLOW CONTROL ENABLE BIT
;
#DEFINE	UART_INP(RID)	CALL UART_INP_IMP \ .DB RID
#DEFINE	UART_OUTP(RID)	CALL UART_OUTP_IMP \ .DB RID
;
;
;
UART_PREINIT:
;
; INIT UART4 BOARD CONFIG REGISTER (NO HARM IF IT IS NOT THERE)
;
	LD	A,$80			; SELECT 7.3728MHZ OSC & LOCK CONFIG REGISTER
	OUT	($CF),A			; DO IT
;
; SETUP THE DISPATCH TABLE ENTRIES
;
	LD	B,UART_CNT		; LOOP CONTROL
	LD	C,0			; PHYSICAL UNIT INDEX
	XOR	A			; ZERO TO ACCUM
	LD	(UART_DEV),A		; CURRENT DEVICE NUMBER
UART_PREINIT0:	
	PUSH	BC			; SAVE LOOP CONTROL
	LD	A,C			; PHYSICAL UNIT TO A
	RLCA				; MULTIPLY BY CFG TABLE ENTRY SIZE (8 BYTES)
	RLCA				; ...
	RLCA				; ... TO GET OFFSET INTO CFG TABLE
	LD	HL,UART_CFG		; POINT TO START OF CFG TABLE
	CALL	ADDHLA			; HL := ENTRY ADDRESS
	PUSH	HL			; SAVE IT
	PUSH	HL			; COPY CFG DATA PTR
	POP	IY			; ... TO IY
	CALL	UART_INITUNIT		; HAND OFF TO GENERIC INIT CODE
	POP	DE			; GET ENTRY ADDRESS BACK, BUT PUT IN DE
	POP	BC			; RESTORE LOOP CONTROL
;
	LD	A,(IY + 1)		; GET THE UART TYPE DETECTED
	OR	A			; SET FLAGS
	JR	Z,UART_PREINIT2		; SKIP IT IF NOTHING FOUND
;	
	PUSH	BC			; SAVE LOOP CONTROL
	LD	BC,UART_DISPATCH	; BC := DISPATCH ADDRESS
	CALL	NZ,CIO_ADDENT		; ADD ENTRY IF UART FOUND, BC:DE
	POP	BC			; RESTORE LOOP CONTROL
;
UART_PREINIT2:	
	INC	C			; NEXT PHYSICAL UNIT
	DJNZ	UART_PREINIT0		; LOOP UNTIL DONE
	XOR	A			; SIGNAL SUCCESS
	RET				; AND RETURN
;
; UART INITIALIZATION ROUTINE
;
UART_INITUNIT:
	; DETECT THE UART TYPE
	CALL	UART_DETECT		; DETERMINE UART TYPE
	LD	(IY + 1),A		; ALSO SAVE IN CONFIG TABLE
	OR	A			; SET FLAGS
	RET	Z			; ABORT IF NOTHING THERE
	
	; UPDATE WORKING UART DEVICE NUM
	LD	HL,UART_DEV		; POINT TO CURRENT UART DEVICE NUM
	LD	A,(HL)			; PUT IN ACCUM
	INC	(HL)			; INCREMENT IT (FOR NEXT LOOP)
	LD	(IY),A			; UDPATE UNIT NUM
	
	; SET DEFAULT CONFIG
	LD	DE,-1			; LEAVE CONFIG ALONE
	JP	UART_INITDEV		; IMPLEMENT IT AND RETURN
;
;
;
;
UART_INIT:
	LD	B,UART_CNT		; COUNT OF POSSIBLE UART UNITS
	LD	C,0			; INDEX INTO UART CONFIG TABLE
UART_INIT1:
	PUSH	BC			; SAVE LOOP CONTROL
	
	LD	A,C			; PHYSICAL UNIT TO A
	RLCA				; MULTIPLY BY CFG TABLE ENTRY SIZE (8 BYTES)
	RLCA				; ...
	RLCA				; ... TO GET OFFSET INTO CFG TABLE
	LD	HL,UART_CFG		; POINT TO START OF CFG TABLE
	CALL	ADDHLA			; HL := ENTRY ADDRESS
	PUSH	HL			; COPY CFG DATA PTR
	POP	IY			; ... TO IY
	
	LD	A,(IY + 1)		; GET UART TYPE
	OR	A			; SET FLAGS
	CALL	NZ,UART_PRTCFG		; PRINT IF NOT ZERO
	
	POP	BC			; RESTORE LOOP CONTROL
	INC	C			; NEXT UNIT
	DJNZ	UART_INIT1		; LOOP TILL DONE
;
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
;
;
UART_DISPATCH:
	; DISPATCH TO FUNCTION HANDLER
	PUSH	HL			; SAVE HL FOR NOW
	LD	A,B			; GET FUNCTION
	AND	$0F			; ISOLATE LOW NIBBLE
	RLCA				; X 2 FOR WORD OFFSET INTO FUNCTION TABLE
	LD	HL,UART_FTBL		; START OF FUNC TABLE
	CALL	ADDHLA			; HL := ADDRESS OF ADDRESS OF FUNCTION
	LD	A,(HL)			; DEREF HL
	INC	HL			; ...
	LD	H,(HL)			; ...
	LD	L,A			; ... TO GET ADDRESS OF FUNCTION
	EX	(SP),HL			; RESTORE HL & PUT FUNC ADDRESS -> (SP)
	RET				; EFFECTIVELY A JP TO TGT ADDRESS

UART_FTBL:
	.DW	UART_IN
	.DW	UART_OUT
	.DW	UART_IST
	.DW	UART_OST
	.DW	UART_INITDEV
	.DW	UART_QUERY
	.DW	UART_DEVICE
;
;
;
UART_IN:
	CALL	UART_IST		; RECEIVED CHAR READY?
	JR	Z,UART_IN		; LOOP IF NOT
	LD	C,(IY + 2)		; C := BASE UART PORT (WHICH IS ALSO RBR REG)
	IN	E,(C)			; CHAR READ TO E
	XOR	A			; SIGNAL SUCCESS
	RET				; AND DONE
;
;
;
UART_OUT:
	CALL	UART_OST		; READY FOR CHAR?
	JR	Z,UART_OUT		; LOOP IF NOT
	LD	C,(IY + 2)		; C := BASE UART PORT (WHICH IS ALSO THR REG)
	OUT	(C),E			; SEND CHAR FROM E
	XOR	A			; SIGNAL SUCCESS
	RET
;
;
;
UART_IST:
	LD	C,(IY + 3)		; C := LINE STATUS REG (LSR)
	IN	A,(C)			; GET STATUS
	AND	$01			; ISOLATE BIT 0 (RECEIVE DATA READY)
	JP	Z,CIO_IDLE		; NOT READY, RETURN VIA IDLE PROCESSING
	XOR	A			; ZERO ACCUM
	INC	A			; ACCUM := 1 TO SIGNAL 1 CHAR WAITING
	RET				; DONE
;
;
;
UART_OST:
	LD	C,(IY + 3)		; C := LINE STATUS REG (LSR)
	IN	A,(C)			; GET STATUS
	AND	$20			; ISOLATE BIT 5 ()
	JP	Z,CIO_IDLE		; NOT READY, RETURN VIA IDLE PROCESSING
	XOR	A			; ZERO ACCUM
	INC	A			; ACCUM := 1 TO SIGNAL 1 BUFFER POSITION
	RET				; DONE
;
;
;
UART_INITDEV:
	; TEST FOR -1 WHICH MEANS USE CURRENT CONFIG (JUST REINIT)
	LD	A,D			; TEST DE FOR
	AND	E			; ... VALUE OF -1
	INC	A			; ... SO Z SET IF -1
	JR	NZ,UART_INITDEV1	; IF DE == -1, REINIT CURRENT CONFIG
;
	; LOAD EXISTING CONFIG TO REINIT
	LD	E,(IY + 4)		; LOW BYTE
	LD	D,(IY + 5)		; HIGH BYTE
;
UART_INITDEV1:
	; DETERMINE DIVISOR
	PUSH	DE			; SAVE CONFIG
	CALL	UART_COMPDIV		; COMPUTE DIVISOR TO BC
	POP	DE			; RESTORE CONFIG
	RET	NZ			; ABORT IF COMPDIV FAILS!
;
	; GOT A DIVISOR, COMMIT NEW CONFIG
	LD	(IY + 4),E		; SAVE LOW WORD
	LD	(IY + 5),D		; SAVE HI WORD
;
	; START OF ACTUAL UART CONFIGURATION
	LD	A,80H			; DLAB IS BIT 7 OF LCR
	UART_OUTP(UART_LCR)		; DLAB ON
	LD	A,B
	UART_OUTP(UART_DLM)		; SET DIVISOR (MS)
	LD	A,C
	UART_OUTP(UART_DLL)		; SET DIVISOR (LS)
;
	; SETUP FCR (DLAB MUST STILL BE ON FOR ACCESS TO BIT 5)
	LD	A,%00100111		; FIFO ENABLE & RESET, 64 BYTE FIFO ENABLE ON 750+
	UART_OUTP(UART_FCR)		; DO IT
;
	; SETUP LCR FROM SECOND CONFIG BYTE (DLAB IS CLEARED)
	LD	A,(IY + 4)		; GET CONFIG BYTE
	AND	~$C0			; ISOLATE PARITY, STOP/DATA BITS
	UART_OUTP(UART_LCR)		; SAVE IT
;
	; SETUP MCR FROM FIRST CONFIG BYTE
	LD	A,(IY + 5)		; GET CONFIG BYTE
	AND	~$1F			; REMOVE ENCODED BAUD RATE BITS
	OR	$03			; FORCE RTS & DTR
	UART_OUTP(UART_MCR)		; SAVE IT
;
	; TEST FOR EFR CAPABLE CHIPS
	LD	A,(IY + 1)		; GET UART TYPE
	CP	UART_16650		; 16650?
	JR	Z,UART_INITDEV2		; USE EFR REGISTER
	CP	UART_16850		; 16850?
	JR	Z,UART_INITDEV2		; USE EFR REGISTER
	JR	UART_INITDEV4		; NO EFT, SKIP AHEAD
;
UART_INITDEV2:
	; WE HAVE AN EFR CAPABLE CHIP, SET EFR REGISTER
	UART_INP(UART_LCR)		; GET CURRENT LCR VALUE
	PUSH	AF			; SAVE IT
	LD	A,$BF			; VALUE TO ACCESS EFR
	UART_OUTP(UART_LCR)		; SET VALUE IN LCR
	LD	A,(IY + 5)		; GET CONFIG BYTE
	BIT	5,A			; AFC REQUESTED?
	LD	A,$C0			; ASSUME AFC ON
	JR	NZ,UART_INITDEV3	; YES, IMPLEMENT IT
	XOR	A			; NO AFC REQEUST, EFR := 0
;
UART_INITDEV3:
	UART_OUTP(UART_EFR)		; SAVE IT
	POP	AF			; RECOVER ORIGINAL LCR VALUE
	UART_OUTP(UART_LCR)		; AND PUT IT BACK
;
UART_INITDEV4:
#IF (UART_DEBUG)
	PRTS(" [$")
	
	; DEBUG: DUMP UART TYPE
	LD	A,(IY + 1)
	CALL	PRTHEXBYTE

	; DEBUG: DUMP IIR
	UART_INP(UART_IIR)
	CALL	PC_SPACE
	CALL	PRTHEXBYTE

	; DEBUG: DUMP LCR
	UART_INP(UART_LCR)
	CALL	PC_SPACE
	CALL	PRTHEXBYTE

	; DEBUG: DUMP MCR
	UART_INP(UART_MCR)
	CALL	PC_SPACE
	CALL	PRTHEXBYTE

	; DEBUG: DUMP EFR
	UART_INP(UART_LCR)
	PUSH	AF
	LD	A,$BF
	UART_OUTP(UART_LCR)
	UART_INP(UART_EFR)
	LD	H,A
	EX	(SP),HL
	LD	A,H
	UART_OUTP(UART_LCR)
	POP	AF
	CALL	PC_SPACE
	CALL	PRTHEXBYTE
	
	PRTC(']')
#ENDIF
;
	XOR	A			; SIGNAL SUCCESS
	RET
;
;
;
UART_QUERY:
	LD	E,(IY + 4)		; FIRST CONFIG BYTE TO E
	LD	D,(IY + 5)		; SECOND CONFIG BYTE TO D
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
;
;
UART_DEVICE:
	LD	D,CIODEV_UART	; D := DEVICE TYPE
	LD	E,(IY)		; E := PHYSICAL UNIT
	XOR	A		; SIGNAL SUCCESS
	RET
;
; UART DETECTION ROUTINE
;
UART_DETECT:
;
	; SEE IF UART IS THERE BY CHECKING DLAB FUNCTIONALITY
	XOR	A			; ZERO ACCUM
	UART_OUTP(UART_IER)		; IER := 0
	LD	A,$80			; DLAB BIT ON
	UART_OUTP(UART_LCR)		; OUTPUT TO LCR (DLAB REGS NOW ACTIVE)
	LD	A,$5A			; LOAD TEST VALUE
	UART_OUTP(UART_DLM)		; OUTPUT TO DLM
	UART_INP(UART_DLM)		; READ IT BACK
	CP	$5A			; CHECK FOR TEST VALUE
	JP	NZ,UART_DETECT_NONE	; NOPE, UNKNOWN UART OR NOT PRESENT
	XOR	A			; DLAB BIT OFF
	UART_OUTP(UART_LCR)		; OUTPUT TO LCR (DLAB REGS NOW INACTIVE)
	UART_INP(UART_IER)		; READ IER
	CP	$5A			; CHECK FOR TEST VALUE
	JP	Z,UART_DETECT_NONE	; IF STILL $5A, UNKNOWN OR NOT PRESENT
;
	; TEST FOR FUNCTIONAL SCRATCH REG, IF NOT, WE HAVE AN 8250
	LD	A,$5A			; LOAD TEST VALUE
	UART_OUTP(UART_SCR)		; PUT IT IN SCRATCH REGISTER
	UART_INP(UART_SCR)		; READ IT BACK
	CP	$5A			; CHECK IT
	JR	NZ,UART_DETECT_8250	; STUPID 8250
;
	; TEST FOR EFR REGISTER WHICH IMPLIES 16650/850
	LD	A,$BF			; VALUE TO ENABLE EFR
	UART_OUTP(UART_LCR)		; WRITE IT TO LCR
	UART_INP(UART_SCR)		; READ SCRATCH REGISTER
	CP	$5A			; SPR STILL THERE?
	JR	NZ,UART_DETECT1		; NOPE, HIDDEN, MUST BE 16650/850
;
	; RESET LCR TO DEFAULT
	LD	A,$80			; DLAB BIT ON
	UART_OUTP(UART_LCR)		; RESET LCR
;
	; TEST FCR TO ISOLATE 16450/550/550A
	LD	A,$E7			; TEST VALUE
	UART_OUTP(UART_FCR)		; PUT IT IN FCR
	UART_INP(UART_IIR)		; READ BACK FROM IIR
	BIT	6,A			; BIT 6 IS FIFO ENABLE, LO BIT
	JR	Z,UART_DETECT_16450	; IF NOT SET, MUST BE 16450
	BIT	7,A			; BIT 7 IS FIFO ENABLE, HI BIT
	JR	Z,UART_DETECT_16550	; IF NOT SET, MUST BE 16550
	BIT	5,A			; BIT 5 IS 64 BYTE FIFO
	JR	Z,UART_DETECT2		; IF NOT SET, MUST BE 16550A/C
	JR	UART_DETECT_16750	; ONLY THING LEFT IS 16750
;
UART_DETECT1:	; PICK BETWEEN 16650/850
	; NOT SURE HOW TO DIFFERENTIATE 16650 FROM 16850 YET
	JR	UART_DETECT_16650	; ASSUME 16650
	RET
;
UART_DETECT2:	; PICK BETWEEN 16550A/C
	; SET AFC BIT IN FCR
	LD	A,$20			; SET AFC BIT, MCR:5
	UART_OUTP(UART_MCR)		; WRITE NEW FCR VALUE
;
	; READ IT BACK, IF SET, WE HAVE 16550C
	UART_INP(UART_MCR)		; READ BACK MCR
	BIT	5,A			; CHECK AFC BIT
	JR	Z,UART_DETECT_16550A	; NOT SET, SO 16550A
	JR	UART_DETECT_16550C	; IS SET, SO 16550C
;
UART_DETECT_NONE:
	LD	A,(IY + 2)		; BASE IO PORT
	CP	$68			; IS THIS PRIMARY SBC PORT?
	JR	Z,UART_DETECT_8250	; SPECIAL CASE FOR PRIMARY UART!
	LD	A,UART_NONE		; IF SO, TREAT AS 8250 NO MATTER WHAT
	RET
;
UART_DETECT_8250:
	LD	A,UART_8250
	RET
;
UART_DETECT_16450:
	LD	A,UART_16450
	RET
;
UART_DETECT_16550:
	LD	A,UART_16550
	RET
;
UART_DETECT_16550A:
	LD	A,UART_16550A
	RET
;
UART_DETECT_16550C:
	LD	A,UART_16550C
	RET
;
UART_DETECT_16650:
	LD	A,UART_16650
	RET
;
UART_DETECT_16750:
	LD	A,UART_16750
	RET
;
UART_DETECT_16850:
	LD	A,UART_16850
	RET
;
; COMPUTE DIVISOR TO BC
;
UART_COMPDIV:
	; WE WANT TO DETERMINE A DIVISOR FOR THE UART CLOCK
	; THAT RESULTS IN THE DESIRED BAUD RATE.
	; BAUD RATE = UART CLK / DIVISOR, OR TO SOLVE FOR DIVISOR
	; DIVISOR = UART CLK / BAUDRATE.
	; THE UART CLOCK IS THE UART OSC PRESCALED BY 16.  ALSO, WE CAN
	; TAKE ADVANTAGE OF ENCODED BAUD RATES ALWAYS BEING A FACTOR OF 75.
	; SO, WE CAN USE (UART OSC / 16 / 75) / (BAUDRATE / 75)
;
	; FIRST WE DECODE THE BAUDRATE, BUT WE USE A CONSTANT OF 1 INSTEAD
	; OF THE NORMAL 75.  THIS PRODUCES (BAUDRATE / 75).
;
	LD	A,D			; GET CONFIG MSB
	AND	$1F			; ISOLATE ENCODED BAUD RATE
	LD	L,A			; PUT IN L
	LD	H,0			; H IS ALWAYS ZERO
	LD	DE,1			; USE 1 FOR ENCODING CONSTANT
	CALL	DECODE			; DE:HL := BAUD RATE, ERRORS IGNORED
	EX	DE,HL			; DE := (BAUDRATE / 75), DISCARD HL
	LD	HL,UARTOSC / 16 / 75	; HL := (UART OSC / 16 / 75)
	JP	DIV16			; BC := HL/DE == DIVISOR AND RETURN
;
;
;
UART_PRTCFG:
	; ANNOUNCE PORT
	CALL	NEWLINE			; FORMATTING
	PRTS("UART$")			; FORMATTING
	LD	A,(IY)			; DEVICE NUM
	CALL	PRTDECB			; PRINT DEVICE NUM
	PRTS(": IO=0x$")		; FORMATTING
	LD	A,(IY + 2)		; GET BASE PORT
	CALL	PRTHEXBYTE		; PRINT BASE PORT

	; PRINT THE UART TYPE
	CALL	PC_SPACE		; FORMATTING
	LD	A,(IY + 1)		; GET UART TYPE BYTE
	RLCA				; MAKE IT A WORD OFFSET
	LD	HL,UART_TYPE_MAP	; POINT HL TO TYPE MAP TABLE
	CALL	ADDHLA			; HL := ENTRY
	LD	E,(HL)			; DEREFERENCE
	INC	HL			; ...
	LD	D,(HL)			; ... TO GET STRING POINTER
	CALL	WRITESTR		; PRINT IT
;
	; ALL DONE IF NO UART WAS DETECTED
	LD	A,(IY + 1)		; GET UART TYPE BYTE
	OR	A			; SET FLAGS
	RET	Z			; IF ZERO, NOT PRESENT
;
	PRTS(" MODE=$")			; FORMATTING
	LD	E,(IY + 4)		; LOAD CONFIG
	LD	D,(IY + 5)		; ... WORD TO DE
	CALL	PS_PRTSC0		; PRINT CONFIG
;
;	; PRINT FEATURES ENABLED
;	LD	A,(UART_FEAT)
;	BIT	UART_FIFO,A
;	JR	Z,UART_INITUNIT2
;	PRTS(" FIFO$")
;UART_INITUNIT2:
;	BIT	UART_AFC,A
;	JR	Z,UART_INITUNIT3
;	PRTS(" AFC$")
;UART_INITUNIT3:
;
	XOR	A
	RET
;
; ROUTINES TO READ/WRITE PORTS INDIRECTLY
;
; READ VALUE OF UART PORT ON TOS INTO REGISTER A
;
UART_INP_IMP:
	EX	(SP),HL		; SWAP HL AND TOS
	PUSH	BC		; PRESERVE BC
	LD	A,(IY + 2)	; GET UART IO BASE PORT
	OR	(HL)		; OR IN REGISTER ID BITS
	LD	C,A		; C := PORT
	IN	A,(C)		; READ PORT INTO A
	POP	BC		; RESTORE BC
	INC	HL		; BUMP HL PAST REG ID PARM
	EX	(SP),HL		; SWAP BACK HL AND TOS
	RET
;
; WRITE VALUE IN REGISTER A TO UART PORT ON TOS
;
UART_OUTP_IMP:
	EX	(SP),HL		; SWAP HL AND TOS
	PUSH	BC		; PRESERVE BC
	LD	B,A		; PUT VALUE TO WRITE IN B
	LD	A,(IY + 2)	; GET UART IO BASE PORT
	OR	(HL)		; OR IN REGISTER ID BITS
	LD	C,A		; C := PORT
	OUT	(C),B		; WRITE VALUE TO PORT
	POP	BC		; RESTORE BC
	INC	HL		; BUMP HL PAST REG ID PARM
	EX	(SP),HL		; SWAP BACK HL AND TOS
	RET
;
;
;
UART_TYPE_MAP:
			.DW	UART_STR_NONE
			.DW	UART_STR_8250
			.DW	UART_STR_16450
			.DW	UART_STR_16550
			.DW	UART_STR_16550A
			.DW	UART_STR_16550C
			.DW	UART_STR_16650
			.DW	UART_STR_16750
			.DW	UART_STR_16850

UART_STR_NONE		.DB	"<NOT PRESENT>$"
UART_STR_8250		.DB	"8250$"
UART_STR_16450		.DB	"16450$"
UART_STR_16550		.DB	"16550$"
UART_STR_16550A		.DB	"16550A$"
UART_STR_16550C		.DB	"16550C$"
UART_STR_16650		.DB	"16650$"
UART_STR_16750		.DB	"16750$"
UART_STR_16850		.DB	"16850$"
;
UART_PAR_MAP		.DB	"NONENMNS"
;
; WORKING VARIABLES
;
UART_DEV		.DB	0		; DEVICE NUM USED DURING INIT
;
; UART PORT TABLE
;
UART_CFG:
#IF ((PLATFORM == PLT_SBC) | (PLATFORM == PLT_ZETA) | (PLATFORM == PLT_ZETA2))
	; SBC/ZETA ONBOARD SERIAL PORT
	.DB	0				; DEVICE NUMBER (UPDATED DURING INIT)
	.DB	0				; UART TYPE
	.DB	$68				; IO PORT BASE (RBR, THR)
	.DB	$68 + UART_LSR			; LINE STATUS PORT (LSR)
	.DW	DEFSERCFG			; LINE CONFIGURATION
	.FILL	2,$FF				; FILLER
#ENDIF
#IF (PLATFORM == PLT_SBC) | (PLATFORM == PLT_N8) | (PLATFORM == PLT_MK4))
	; CASSETTE INTERFACE SERIAL PORT
	.DB	0				; DEVICE NUMBER (UPDATED DURING INIT)
	.DB	0				; UART TYPE
	.DB	$80				; IO PORT BASE (RBR, THR)
	.DB	$80 + UART_LSR			; LINE STATUS PORT (LSR)
	.DW	SER_300_8N1			; LINE CONFIGURATION
	.FILL	2,$FF				; FILLER
#ENDIF
#IF (PLATFORM == PLT_SBC)
	; MF/PIC SERIAL PORT
	.DB	0				; DEVICE NUMBER (UPDATED DURING INIT)
	.DB	0				; UART TYPE
	.DB	$48				; IO PORT BASE (RBR, THR)
	.DB	$48 + UART_LSR			; LINE STATUS PORT (LSR)
	.DW	DEFSERCFG			; LINE CONFIGURATION
	.FILL	2,$FF				; FILLER
#ENDIF
#IF (PLATFORM == PLT_SBC) | (PLATFORM == PLT_N8) | (PLATFORM == PLT_MK4))
	; 4UART SERIAL PORT A
	.DB	0				; DEVICE NUMBER (UPDATED DURING INIT)
	.DB	0				; UART TYPE
	.DB	$C0				; IO PORT BASE (RBR, THR)
	.DB	$C0 + UART_LSR			; LINE STATUS PORT (LSR)
	.DW	DEFSERCFG			; LINE CONFIGURATION
	.FILL	2,$FF				; FILLER
#ENDIF
#IF (PLATFORM == PLT_SBC) | (PLATFORM == PLT_N8) | (PLATFORM == PLT_MK4))
	; 4UART SERIAL PORT B
	.DB	0				; DEVICE NUMBER (UPDATED DURING INIT)
	.DB	0				; UART TYPE
	.DB	$C8				; IO PORT BASE (RBR, THR)
	.DB	$C8 + UART_LSR			; LINE STATUS PORT (LSR)
	.DW	DEFSERCFG			; LINE CONFIGURATION
	.FILL	2,$FF				; FILLER
#ENDIF
#IF (PLATFORM == PLT_SBC) | (PLATFORM == PLT_N8) | (PLATFORM == PLT_MK4))
	; 4UART SERIAL PORT C
	.DB	0				; DEVICE NUMBER (UPDATED DURING INIT)
	.DB	0				; UART TYPE
	.DB	$D0				; IO PORT BASE (RBR, THR)
	.DB	$D0 + UART_LSR			; LINE STATUS PORT (LSR)
	.DW	DEFSERCFG			; LINE CONFIGURATION
	.FILL	2,$FF				; FILLER
#ENDIF
#IF (PLATFORM == PLT_SBC) | (PLATFORM == PLT_N8) | (PLATFORM == PLT_MK4))
	; 4UART SERIAL PORT D
	.DB	0				; DEVICE NUMBER (UPDATED DURING INIT)
	.DB	0				; UART TYPE
	.DB	$D8				; IO PORT BASE (RBR, THR)
	.DB	$D8 + UART_LSR			; LINE STATUS PORT (LSR)
	.DW	DEFSERCFG			; LINE CONFIGURATION
	.FILL	2,$FF				; FILLER
#ENDIF
;
UART_CNT	.EQU	($ - UART_CFG) / 8
