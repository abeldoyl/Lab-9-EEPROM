    ; Abel Doyle
    ; RCET3375
    ; Lab9-1EEPROM
    ;git url
    
; PIC16F883 Configuration Bit Settings

; Assembly source line config statements

; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3/MCLR pin function is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit (Program memory code protection is disabled)
  CONFIG  CPD = OFF             ; Data Code Protection bit (Data memory code protection is disabled)
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits (BOR disabled)
  CONFIG  IESO = OFF            ; Internal External Switchover bit (Internal/External Switchover mode is disabled)
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor Enabled bit (Fail-Safe Clock Monitor is disabled)
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit (RB3 pin has digital I/O, HV on MCLR must be used for programming)

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset Selection bit (Brown-out Reset set to 4.0V)
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits (Write protection off)

; config statements should precede project file includes.
#include <xc.inc>
; ---- Bank 0 variables ----
 SysFlags    EQU 0x20   ; system flag byte (bit numbers below)
 BtnEvents   EQU 0x21   ; button event flags set by ServiceTick, cleared by ServiceButtons
 BtnState    EQU 0x22   ; debounced button levels: bit = 1 released (HIGH), 0 pressed
 selCount    EQU 0x23   ; Select debounce counter (ticks)
 wrCount     EQU 0x24   ; Write debounce counter (ticks)
 diff        EQU 0x25   ; scratch: which pins differ from their debounced level
 pending     EQU 0x26   ; RAM selection ('A' or 'B')
 stored      EQU 0x27   ; value last read from EEPROM

; ---- SysFlags bit numbers ----
 selecting   EQU 0      ; 1 = Write held, selection mode active

; ---- BtnEvents bit numbers ----
 sel_press   EQU 0      ; debounced Select press
 wr_press    EQU 1      ; debounced Write press
 wr_release  EQU 2      ; debounced Write release

; ---- Button pin / BtnState bit numbers (RB0 = Select, RB1 = Write) ----
 sel_bit     EQU 0
 wr_bit      EQU 1

; ---- Constants ----
 DEBOUNCE_TICKS EQU 20  ; a pin must differ from its stable level for 20 ticks
                        ; (~1.024 ms each at 4 MHz, TMR0 prescaler 1:4) = ~20 ms
 ZFLAG       EQU 2      ; STATUS bit 2 = Z

PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup

PSECT code,class=CODE,delta=2

; SETUP - runs once after reset, then falls into Main.
; No interrupts are used. TMR0 free-runs as a ~1 ms tick that Main polls.
; No EEPROM write happens here. Setup leaves Bank 0 selected.
Setup:
    BANKSEL ANSEL
    CLRF ANSEL              ; all pins digital (RA1/RA2 share AN1/AN2)
    CLRF ANSELH             ; RB0/RB1 share AN12/AN10

    BANKSEL TRISA
    MOVLW 0xF9
    MOVWF TRISA             ; RA1, RA2 = outputs (read / write diagnostics)
    MOVLW 0xFF
    MOVWF TRISB             ; PORTB inputs (RB0 Select, RB1 Write)
    CLRF TRISC              ; PORTC outputs to DLG7137 D0-D6

    MOVLW 0x03
    MOVWF WPUB              ; weak pull-ups on RB0 and RB1
    MOVLW 0x01
    MOVWF OPTION_REG        ; RBPU = 0 (pull-ups on); TMR0 = internal clock,
                            ; prescaler 1:4 -> overflow every 1.024 ms

    BANKSEL EEADR
    CLRF EEADR              ; EEPROM address 0x00 (never changes in this lab)
    BANKSEL EECON1
    BCF EECON1,7            ; EEPGD = 0 -> data EEPROM, not program flash

    BANKSEL PORTA
    CLRF PORTA              ; RA1, RA2 diagnostics start LOW
    CLRF PORTC
    CLRF INTCON             ; GIE = 0, T0IF = 0
    CLRF SysFlags           ; not selecting
    MOVLW 0x41
    MOVWF pending
    CLRF BtnEvents          ; no events
    CLRF selCount
    CLRF wrCount
    MOVLW 0x03
    MOVWF BtnState          ; both buttons start as "released"

; MAIN - runs the three services in a fixed order, forever.
; Nothing in Main waits (except the ~5 ms EEPROM write), so ServiceTick
; is reached far more often than once per millisecond.
Main:
    CALL ServiceTick        ; debounce both buttons, raise press/release events
    CALL ServiceButtons     ; act on events (selection mode, the one write)
    CALL ServiceStored      ; read EEPROM and display it when not selecting
    goto Main

; SERVICE TICK - debounces both buttons once per TMR0 overflow (~1 ms).
; A pin that differs from its stable level for DEBOUNCE_TICKS ticks in a row
; becomes the new stable level and raises one event. Any tick where the pin
; matches the stable level restarts the count, so bounce is ignored on both
; the press and the release.
ServiceTick:
    BTFSS INTCON,2          ; T0IF set? (about 1 ms has passed)
    RETURN                  ; no: nothing to do
    BCF INTCON,2            ; clear the tick flag

    MOVF PORTB,W
    XORWF BtnState,W        ; bit = 1 where the pin differs from its stable level
    MOVWF diff

    BTFSS diff,sel_bit      ; Select differs?
    goto SelSteady
    INCF selCount,F
    MOVLW DEBOUNCE_TICKS
    XORWF selCount,W
    BTFSS STATUS,ZFLAG      ; reached the debounce count?
    goto TickWrite
    CLRF selCount
    MOVLW 0x01
    XORWF BtnState,F        ; accept the new Select level
    BTFSS BtnState,sel_bit  ; new level LOW = press
    BSF BtnEvents,sel_press ; (Select release produces no event)
    goto TickWrite
SelSteady:
    CLRF selCount

TickWrite:
    BTFSS diff,wr_bit       ; Write differs?
    goto WrSteady
    INCF wrCount,F
    MOVLW DEBOUNCE_TICKS
    XORWF wrCount,W
    BTFSS STATUS,ZFLAG
    RETURN
    CLRF wrCount
    MOVLW 0x02
    XORWF BtnState,F        ; accept the new Write level
    BTFSC BtnState,wr_bit   ; new level HIGH = release
    goto WrReleased
    BSF BtnEvents,wr_press
    RETURN
WrReleased:
    BSF BtnEvents,wr_release
    RETURN
WrSteady:
    CLRF wrCount
    RETURN

; SERVICE BUTTONS - turns debounced events into actions.
;   Normal mode:    Select press ignored; Write press starts selection (no write).
;   Selecting mode: Select press toggles A/B; Write release saves ONCE and exits.
; WriteEEPROM is called only from here, only on a debounced Write release.
ServiceButtons:
    BTFSC SysFlags,selecting
    goto SelectingMode

    BCF BtnEvents,sel_press ; Select alone does nothing
    BCF BtnEvents,wr_release
    BTFSS BtnEvents,wr_press
    RETURN
    BCF BtnEvents,wr_press
    BSF SysFlags,selecting
    CALL ShowPending
    RETURN

SelectingMode:
    BTFSS BtnEvents,sel_press
    goto CheckRelease
    BCF BtnEvents,sel_press
    MOVLW 0x03
    XORWF pending,F         ; 'A' (0x41) <-> 'B' (0x42)
    CALL ShowPending

CheckRelease:
    BTFSS BtnEvents,wr_release
    RETURN
    BCF BtnEvents,wr_release
    BCF SysFlags,selecting
    MOVF pending,W
    CALL WriteEEPROM        ; the ONLY EEPROM write in the program
    RETURN

; SHOW PENDING - displays the RAM selection on the DLG7137.
ShowPending:
    MOVF pending,W
    MOVWF PORTC
    RETURN

; SERVICE STORED - when not selecting, reads EEPROM every pass and displays
; A, B, or ? for any other value. The read pulse on RA1 is inside ReadEEPROM,
; so display time is not part of it.
ServiceStored:
    BTFSC SysFlags,selecting
    RETURN                  ; selection is shown by ServiceButtons
    CALL ReadEEPROM         ; W = EEPROM[0x00]
    MOVWF stored

    MOVF stored,W
    XORLW 0x41
    BTFSC STATUS,ZFLAG
    goto ShowA
    MOVF stored,W
    XORLW 0x42
    BTFSC STATUS,ZFLAG
    goto ShowB
    MOVLW 0x3F               ; '?' unrecognised data
    MOVWF PORTC
    RETURN
ShowA:
    MOVLW 0x41
    MOVWF PORTC
    RETURN
ShowB:
    MOVLW 0x42
    MOVWF PORTC
    RETURN

; READ EEPROM - returns EEPROM[0x00] in W. RA1 is HIGH only around the read.
; Bank 0 on entry and exit. EEADR and EEPGD were set once in Setup.
ReadEEPROM:
    BSF PORTA,1             ; RA1 HIGH
    BANKSEL EECON1
    BSF EECON1,0            ; RD = 1 (data is valid the next cycle)
    BANKSEL EEDATA
    MOVF EEDATA,W
    BANKSEL PORTA
    BCF PORTA,1             ; RA1 LOW
    RETURN

; WRITE EEPROM - writes W to EEPROM[0x00] and waits for it to finish.
; RA2 is HIGH from just before the unlock sequence until WR clears.
; Bank 0 on entry and exit. Interrupts are never enabled; GIE is cleared
; again here so the unlock sequence is guaranteed uninterrupted.
WriteEEPROM:
    BANKSEL EEDATA
    MOVWF EEDATA             ; data to write
    BANKSEL EECON1
    BSF EECON1,2            ; WREN = 1
    BANKSEL PORTA
    BSF PORTA,2             ; RA2 HIGH
    BANKSEL EECON1
    BCF INTCON,7            ; GIE = 0

    ; ---- required unlock sequence: no other instructions in between ----
    MOVLW 0x55
    MOVWF EECON2
    MOVLW 0xAA
    MOVWF EECON2
    BSF EECON1,1            ; WR = 1 starts the write
    ; --------------------------------------------------------------------

WriteWait:
    BTFSC EECON1,1          ; WR clears when the write is complete
    goto WriteWait
    BCF EECON1,2            ; WREN = 0
    BANKSEL PIR2
    BCF PIR2,4              ; clear EEIF
    BANKSEL PORTA
    BCF PORTA,2             ; RA2 LOW
    RETURN
End