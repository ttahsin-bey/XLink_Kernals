;
; XLink-Kernal für Junior Computer ][
;
; (c) 08.2022 Thomas Tahsin-Bey
;
; 
; use acme to assemble this source!
;
; acme -r jc2xlink.lst jc2xlink.asm
;
;
; Revision: 0.5		first official working release
;
;----------------------------------------------------------------

			!cpu	6502
			*=	$f000
			!fill	4096,255
			*=	$fc00, overlay
			!binary "JC-Monitor-FC00_RIOT-at-1A00.bin"
			!to	"jc2xlink_4k.bin", plain

VIA_Adapter		= 0					;set to 1 for Freaks own VIA-Adapter to connect the original C64-XLink...

XLink_Start		= $DC
XLink_End		= $DE

PREG			= $F1
SPUSER			= $F2
ACC			= $F3
YREG			= $F4
XREG			= $F5
BYTES			= $F6
MODE			= $FF

RIOT_Base		= $1A00
RIOT_DRA		= RIOT_Base+$80
RIOT_DRB		= RIOT_Base+$81
RIOT_DDRA		= RIOT_Base+$82
RIOT_DDRB		= RIOT_Base+$83

!if VIA_Adapter {VIA_Base=$1200} else {VIA_Base=$0800}
VIA_ORB			= VIA_Base+$00
VIA_IRB			= VIA_Base+$00
VIA_DDRB		= VIA_Base+$02
VIA_PCR			= VIA_Base+$0c
VIA_IFR			= VIA_Base+$0d
VIA_IER			= VIA_Base+$0e


Original_START		= $FC33

;---------------------------------------------------------------

			*=	$f800, overlay			;eigener Code
XLink_Kernal_Start
XLink_Reset		lda	#%00011110			;PB1-PB4 is output
			sta	RIOT_DDRB
			lda	#%00000000			;Reset P-Register (Interrupts sind während der Programmausführung erlaubt)
			sta	PREG
			lda	#$03
			sta	MODE				;Set AD-Mode
			sta	BYTES				;Display Pointer_High, Pointer_Low, INH
			ldx	#$FF
			txs
			stx	SPUSER
			cld

			lda	#%00000000			;Übertragungs-Port als Eingang setzen
			sta	VIA_DDRB
			lda	#$ee				;CB1 wird Interrupt-Leitung (Low-Aktiv)
			sta	VIA_PCR
			lda	#$90				;Interrupt Enable für CB1
			sta	VIA_IER

			cli					; Interrupts erlauben
			jmp	Original_START


XLink_Interrupt		pha
			txa
			pha
			tya
			pha
			tsx
			lda	$0104,x
			and	#$10				;Break-Flag testen
			bne	XLink_Interrupt_BRK

XLink_Interrupt_noBRK	lda	VIA_IFR				;CB1 ist die /Flag-Leitung
			and	#%00010000
			bne	XLink_Interrupt_Entry		;springen, wenn Interrupt durch das XLink-Modul ausgelöst wurde
XLink_Interrupt_BRK	pla
			tay
			pla
			tax
			pla
			jmp	($1A7E)

XLink_Interrupt_Entry	sta	VIA_IFR				;Irq-Flag rücksetzen
			lda	#%01111111			;Segment-Pattern abschalten (damit das LED-Display ausgeschaltet ist)
			sta	RIOT_DRA
			ldy	VIA_IRB				;Port B einlesen und in Y zwischenspeichern
			jsr	XLink_Acknowledge
			iny
			iny					;jetzt sind wir wertetechnisch zwischen 0 und 9
			tya
			cmp	#10				;Range 0-9 testen
			bcs	XLink_Interrupt_done		;springen, wenn Wert außerhalb des Bereichs liegt (dann ist das Carry-Bit gesetzt)
			lda	XLink_JumpTable_Low,y		;sonst zugehörige Adresse aus der Tabelle lesen
			sta	XLink_Start
			lda	XLink_JumpTable_High,y
			sta	XLink_Start+1
			jmp	(XLink_Start)			;und zu dieser Adresse springen

XLink_JumpTable_Low	!byte	<XLink_Identify, <XLink_Interrupt_done, <XLink_Interrupt_done, <XLink_Load, <XLink_Save
			!byte	<XLink_Poke, <XLink_Peek, <XLink_Jump, <XLink_Run, <XLink_Inject

XLink_JumpTable_High	!byte	>XLink_Identify, >XLink_Interrupt_done, >XLink_Interrupt_done, >XLink_Load, >XLink_Save
			!byte	>XLink_Poke, >XLink_Peek, >XLink_Jump, >XLink_Run, >XLink_Inject

XLink_Interrupt_done	pla
			tay
			pla
			tax
			pla
			rti

;---------------------------------------------------------------

XLink_Read		jsr	XLink_Wait
			ldx	VIA_IRB

XLink_Acknowledge	lda	VIA_PCR
			and	#%00101111
			eor	#%11100000
			sta	VIA_PCR
			rts

XLink_Write		sta	VIA_ORB
			jsr	XLink_Acknowledge

XLink_Wait		lda	VIA_IFR
			and	#%00010000
			beq	XLink_Wait
			sta	VIA_IFR
			rts

;---------------------------------------------------------------

XLink_ReadShortHeader	jsr	XLink_Read
			jsr	XLink_Read
			jsr	XLink_Read
			stx	XLink_Start
			jsr	XLink_Read
			stx	XLink_Start+1
			rts

XLink_ReadLongHeader	jsr	XLink_ReadShortHeader
			jsr	XLink_Read
			stx	XLink_End
			jsr	XLink_Read
			stx	XLink_End+1
			rts

;---------------------------------------------------------------

XLink_Load		jsr	XLink_ReadLongHeader

			ldy	#$00
XLink_Load_Loop		lda	VIA_IFR
			and	#%00010000
			beq	XLink_Load_Loop
			sta	VIA_IFR

			lda	VIA_IRB
			sta	(XLink_Start),y

			lda	VIA_PCR
			and	#%00101111
			eor	#%11100000
			sta	VIA_PCR

			inc	XLink_Start
			bne	XLink_Load_Check
			inc	XLink_Start+1

XLink_Load_Check	lda	XLink_Start+1
			cmp	XLink_End+1
			bne	XLink_Load_Loop
			lda	XLink_Start
			cmp	XLink_End
			bne	XLink_Load_Loop

XLink_Load_End		jmp	XLink_Interrupt_done


;---------------------------------------------------------------

XLink_Save		jsr	XLink_ReadLongHeader
			
XLink_Save_Wait		lda	VIA_IFR
			and	#%00010000
			beq	XLink_Save_Wait
			sta	VIA_IFR

			ldy	#%11111111			;Port B auf Ausgang schalten
			sty	VIA_DDRB
			iny					;Y auf 0 für nachfolgende Ladeefehle setzen

XLink_Save_Loop		lda	(XLink_Start),y			;Inhalt von aktueller Adresse laden
			jsr	XLink_Write			;und übertragen

			inc	XLink_Start			;Adresse erhöhen
			bne	XLink_Save_Check
			inc	XLink_Start+1

XLink_Save_Check	lda	XLink_Start+1			;sind wir schon am Ende angekommen? Nein, dann Schleife wiederholen
			cmp	XLink_End+1
			bne	XLink_Save_Loop
			lda	XLink_Start
			cmp	XLink_End
			bne	XLink_Save_Loop

			sty	VIA_DDRB			;Port B auf Eingang schalten (Y enthält hier den Wert 0)

			jmp	XLink_Interrupt_done

;---------------------------------------------------------------

XLink_Poke		jsr	XLink_ReadShortHeader

			jsr	XLink_Read
			ldy	#0
			txa
			sta	(XLink_Start),y

			jmp	XLink_Interrupt_done

;---------------------------------------------------------------	

XLink_Peek		jsr	XLink_ReadShortHeader

XLink_Peek_Wait		lda	VIA_IFR
			and	#%00010000
			beq	XLink_Peek_Wait
			sta	VIA_IFR

			ldy	#%11111111			;Port B auf Ausgang schalten
			sty	VIA_DDRB
			
			iny
			lda	(XLink_Start),y			;Wert aus angeforderter Speicherzelle lesen
			jsr	XLink_Write			;und übertragen

			sty	VIA_DDRB			;Port B auf Eingang schalten (Y enthält hier den Wert 0)

			jmp	XLink_Interrupt_done

;---------------------------------------------------------------	

XLink_Jump		jsr	XLink_ReadShortHeader

			ldx	SPUSER
			txs
			
			lda	XLink_Start			;Startadresse auf den Stack legen
			pha
			lda	XLink_Start+1
			pha

			lda	PREG
			pha

			ldx	XREG
			ldy	YREG
			lda	ACC
			rti

;--- WORK IN PROGRESS ------------------------------------------	

XLink_Run		ldx	#$ff				;Reset Stack Pointer
			txs
;			lda	#$01				;Cursor Off
;			sta	$cc

;			jsr	$C659				;// Insert new line into BASIC program			;run BASIC Program
;			jsr	$C68E				;// Reset BASIC text pointer
			
;			lda	#$00
;			sta	basic_cmd_mode
			
;			jmp	$C7AE				;// Basic warm start

Dummy_Loop		jmp	Dummy_Loop			;Später anpassen

;--- WORK IN PROGRESS ------------------------------------------	

XLink_Inject		lda	#>XLink_Return
			pha
			lda	#<XLink_Return
			pha
			
			jsr	XLink_Read
			txa
			pha
			jsr	XLink_Read
			txa
			pha

			rts

XLink_Return		nop
			jmp	XLink_Interrupt_done

;---------------------------------------------------------------	

XLink_Identify		lda	VIA_IFR
			and	#%00010000
			beq	XLink_Identify
			sta	VIA_IFR

			ldy	#%11111111
			sty	VIA_DDRB			;Port B auf Ausgang schalten

			ldx	#Identify_Table_End-Identify_Table
			iny
XLink_Identify_Loop	lda	Identify_Table,y
			jsr	XLink_Write
			iny
			dex
			bne	XLink_Identify_Loop

			stx	VIA_DDRB			;Port B auf Eingang schalten
			jmp	XLink_Interrupt_done

Identify_Table		!byte	13				;Server.Size
			!text	"JUNIOR2-XLINK"			;Server.ID
			!byte	$05				;Server.Version (0.5)
			!byte	10				;Server.Machine (10 für Junior Computer 2)
			!byte	1				;Server.Type
			!word	XLink_Kernal_Start		;Server.Start
			!word	XLink_Kernal_End-1		;Server.End
			!word	XLink_Kernal_Start-1		;Server.MemTop
Identify_Table_End

XLink_Kernal_End

			*=	$fffc, overlay			;Reset- und IRQ-Vektor verbiegen
Vectors			!word	XLink_Reset
			!word	XLink_Interrupt


			!endoffile
