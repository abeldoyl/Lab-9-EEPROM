    ; Abel Doyle
    ; RCET3375
    ; Lab9-2EEPROM
    ; https://github.com/abeldoyl/Lab-9-EEPROM/tree/main/Lab9-2EEPROM.X
    
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
; ============================================================================
; EEPROM routine registers (the ONLY RAM the EEPROM routines use).
; Placed in common RAM (0x70-0x7F) so they are reachable from every bank
; without BANKSEL.
; ============================================================================
 ee_address  EQU 0x70   ; EEPROM byte address for read or write
 ee_data     EQU 0x71   ; byte returned by a read / byte being written
 ee_status   EQU 0x72   ; EEPROM status flags (bits below)
 
; ---- ee_status bit numbers ----
 EEPROM_READ  EQU 0     ; 1 = EEPROMRead is running
 EEPROM_WRITE EQU 1     ; 1 = write started, awaiting completion + verify
 EEPROM_ERROR EQU 2     ; 1 = last verify failed
 EEPROM_GIE   EQU 7     ; scratch: saved GIE state during the unlock sequence
                        ; (cleared again before EEPROMWrite returns)
 
 BUSY_MASK    EQU 0x03  ; EEPROM_READ | EEPROM_WRITE (bits 0 and 1)
 
; ============================================================================
; Application variables (Bank 0)
; ============================================================================
 SysFlags    EQU 0x20   ; system flag byte (bit numbers below)
 BtnEvents   EQU 0x21   ; button event flags set by ServiceTick, cleared by ServiceButtons
 BtnState    EQU 0x22   ; debounced button levels: bit = 1 released (HIGH), 0 pressed
 selCount    EQU 0x23   ; Select debounce counter (ticks)
 wrCount     EQU 0x24   ; Write debounce counter (ticks)
 diff        EQU 0x25   ; scratch: which pins differ from their debounced level
 pending     EQU 0x26   ; RAM selection ('A' or 'B')
 selTimeL    EQU 0x27   ; selection timeout countdown, low byte (ticks)
 selTimeH    EQU 0x28   ; selection timeout countdown, high byte
 current_address EQU 0x29 ; EEPROM address used by the application (init 0x00)
 
; ---- SysFlags bit numbers ----
 selecting   EQU 0      ; 1 = selection mode active
 timed_out   EQU 1      ; 1 = selection timeout expired (set by ServiceTick)
 
; ---- BtnEvents bit numbers ----
 sel_press   EQU 0      ; debounced Select press
 wr_press    EQU 1      ; debounced Write press
 
; ---- Button pin / BtnState bit numbers (RB0 = Select, RB1 = Write) ----
 sel_bit     EQU 0
 wr_bit      EQU 1
 
; ---- Constants ----
 DEBOUNCE_TICKS EQU 20  ; a pin must differ from its stable level for 20 ticks
                        ; (~1.024 ms each at 4 MHz, TMR0 prescaler 1:4) = ~20 ms
 TIMEOUT_L   EQU 0xD1   ; 977 ticks x 1.024 ms = ~1.0 s  (977 = 0x03D1)
 TIMEOUT_H   EQU 0x03
 ZFLAG       EQU 2      ; STATUS bit 2 = Z
 
PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup
 
PSECT code,class=CODE,delta=2
 
; SETUP - runs once after reset, then falls into MainLoop.
; No interrupts are used. TMR0 free-runs as a ~1 ms tick that the loop polls.
; No EEPROM write happens here. Setup leaves Bank 0 selected.
Setup:
    BANKSEL ANSEL
    CLRF ANSEL              ; all pins digital
    CLRF ANSELH             ; RB0/RB1 share AN12/AN10
 
    BANKSEL TRISA
    MOVLW 0xF8
    MOVWF TRISA             ; RA0 = selection LED, RA1 = loop pulse, RA2 = error LED (outputs)
    MOVLW 0xFF
    MOVWF TRISB             ; PORTB inputs (RB0 Select, RB1 Write)
    CLRF TRISC              ; PORTC outputs to DLG7137 D0-D6
 
    MOVLW 0x03
    MOVWF WPUB              ; weak pull-ups on RB0 and RB1
    MOVLW 0x01
    MOVWF OPTION_REG        ; RBPU = 0 (pull-ups on); TMR0 = internal clock,
                            ; prescaler 1:4 -> overflow every 1.024 ms
 
    BANKSEL EECON1
    BCF EECON1,7            ; EEPGD = 0 -> data EEPROM
    BCF EECON1,2            ; WREN = 0
 
    BANKSEL PIR2
    BCF PIR2,4              ; clear EEIF
 
    BANKSEL PORTA
    CLRF PORTA              ; RA0, RA1, RA2 start LOW
    CLRF PORTC
    CLRF INTCON             ; GIE = 0, T0IF = 0
    CLRF SysFlags           ; not selecting
    CLRF BtnEvents          ; no events
    CLRF selCount
    CLRF wrCount
    CLRF selTimeL
    CLRF selTimeH
    CLRF ee_address
    CLRF ee_data
    CLRF ee_status
    CLRF current_address    ; test address (change this one value to test others)
    MOVLW 0x03
    MOVWF BtnState          ; both buttons start as "released"
 
; MAINLOOP - fixed order, forever. Nothing here waits for the EEPROM.
MainLoop:
    BSF PORTA,1             ; RA1 diagnostic pulse, once per iteration
    BCF PORTA,1
 
    CALL ServiceWrite       ; if a write finished, call EEPROMVerifyWrite
    CALL ServiceErrorLED    ; RA2 = EEPROM_ERROR
    CALL ServiceTick        ; debounce buttons, count selection timeout
    CALL ServiceTimeout     ; timeout is checked BEFORE the buttons
    CALL ServiceButtons     ; act on button events
    CALL ServiceDisplay     ; pending char while selecting, else stored value
    goto MainLoop
 
; SERVICE WRITE - polling for write completion. EEIF is set when the
; hardware write ends. EEPROMVerifyWrite clears EEIF, so it runs once per write.
ServiceWrite:
    BTFSS ee_status,EEPROM_WRITE
    RETURN                  ; no write pending
    BANKSEL PIR2
    BTFSS PIR2,4            ; EEIF set? (write finished)
    goto WriteStillBusy
    CALL EEPROMVerifyWrite  ; returns in Bank 0
    RETURN
WriteStillBusy:
    BANKSEL PORTA
    RETURN
 
; SERVICE ERROR LED - RA2 follows EEPROM_ERROR every iteration.
ServiceErrorLED:
    BTFSC ee_status,EEPROM_ERROR
    goto ErrorOn
    BCF PORTA,2
    RETURN
ErrorOn:
    BSF PORTA,2
    RETURN
 
; SERVICE TICK - once per TMR0 overflow (~1 ms):
;   1) counts down the selection timeout while selecting
;   2) debounces both buttons.
; A pin that differs from its stable level for DEBOUNCE_TICKS ticks in a row
; becomes the new stable level. Only PRESSES raise events (releases do not).
ServiceTick:
    BTFSS INTCON,2          ; T0IF set? (about 1 ms has passed)
    RETURN                  ; no: nothing to do
    BCF INTCON,2            ; clear the tick flag
 
    ; ---- selection timeout countdown (16-bit) ----
    BTFSS SysFlags,selecting
    goto TickButtons
    MOVF selTimeL,F
    BTFSC STATUS,ZFLAG
    DECF selTimeH,F         ; borrow when low byte is 0
    DECF selTimeL,F
    MOVF selTimeL,W
    IORWF selTimeH,W
    BTFSC STATUS,ZFLAG      ; both bytes zero = timeout
    BSF SysFlags,timed_out
 
TickButtons:
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
    BSF BtnEvents,sel_press
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
    BTFSS BtnState,wr_bit   ; new level LOW = press
    BSF BtnEvents,wr_press
    RETURN
WrSteady:
    CLRF wrCount
    RETURN
 
; SERVICE TIMEOUT - leaves selection mode ~1 s after the last Select press.
; A timeout never starts an EEPROM write.
ServiceTimeout:
    BTFSS SysFlags,timed_out
    RETURN
    BCF SysFlags,timed_out
    BTFSS SysFlags,selecting
    RETURN
    BCF SysFlags,selecting
    BCF PORTA,0             ; RA0 OFF
    RETURN
 
; SERVICE BUTTONS - turns debounced events into actions.
;   Ignored (events discarded) while EEPROM_READ or EEPROM_WRITE is set.
;   EEPROM_ERROR does not block the buttons.
;   Idle:      Select press enters selection (A, RA0 on, timer starts).
;              Write press is ignored.
;   Selecting: Select press toggles A/B and restarts the timer.
;              Write press exits selection and calls EEPROMWrite.
ServiceButtons:
    MOVF ee_status,W
    ANDLW BUSY_MASK
    BTFSC STATUS,ZFLAG
    goto ButtonsEnabled
    CLRF BtnEvents          ; EEPROM busy: ignore button events
    RETURN
 
ButtonsEnabled:
    BTFSC SysFlags,selecting
    goto SelectingMode
 
    BCF BtnEvents,wr_press  ; Write outside selection mode is ignored
    BTFSS BtnEvents,sel_press
    RETURN
    BCF BtnEvents,sel_press
    MOVLW 0x41
    MOVWF pending           ; selection always starts at A
    BSF SysFlags,selecting
    BSF PORTA,0             ; RA0 ON
    CALL ReloadTimeout
    RETURN
 
SelectingMode:
    BTFSS BtnEvents,sel_press
    goto CheckWrite
    BCF BtnEvents,sel_press
    MOVLW 0x03
    XORWF pending,F         ; 'A' (0x41) <-> 'B' (0x42)
    CALL ReloadTimeout
 
CheckWrite:
    BTFSS BtnEvents,wr_press
    RETURN
    BCF BtnEvents,wr_press
    BCF SysFlags,selecting  ; exit selection, stop the timer
    BCF SysFlags,timed_out
    BCF PORTA,0             ; RA0 OFF
    MOVF current_address,W
    MOVWF ee_address
    MOVF pending,W
    MOVWF ee_data
    CALL EEPROMWrite        ; starts the write and returns right away
    RETURN
 
; RELOAD TIMEOUT - restarts the ~1 s selection timer.
ReloadTimeout:
    MOVLW TIMEOUT_L
    MOVWF selTimeL
    MOVLW TIMEOUT_H
    MOVWF selTimeH
    RETURN
 
; SERVICE DISPLAY - DLG7137 on PORTC.
;   Selecting: show the pending character.
;   Write pending: leave PORTC alone (last character stays), no EEPROM read.
;   Otherwise: read EEPROM and show A, B, or ? for anything else.
ServiceDisplay:
    BTFSS SysFlags,selecting
    goto ShowStored
    MOVF pending,W
    MOVWF PORTC
    RETURN
 
ShowStored:
    BTFSC ee_status,EEPROM_WRITE
    RETURN                  ; keep the last character, do not touch EEPROM
    MOVF current_address,W
    MOVWF ee_address
    CALL EEPROMRead         ; ee_data = EEPROM[current_address]
    MOVF ee_data,W
    XORLW 0x41
    BTFSC STATUS,ZFLAG
    goto ShowA
    MOVF ee_data,W
    XORLW 0x42
    BTFSC STATUS,ZFLAG
    goto ShowB
    MOVLW 0x3F              ; '?' unrecognised data
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
 
; ============================================================================
; REUSABLE EEPROM ROUTINES
; Use only ee_address, ee_data, ee_status. Need only the bit EQUs above.
; Each routine is self-contained (no helper calls) -> each uses 1 stack level.
; Deepest call chain in this program: MainLoop -> ServiceButtons ->
; EEPROMWrite = 2 levels (hardware stack is 8). Bank 0 on exit.
; ============================================================================
 
; EEPROMREAD
; In:  ee_address = address to read
; Out: ee_data = byte read. EEPROM_READ is set during the read, cleared on exit.
EEPROMRead:
    BSF ee_status,EEPROM_READ
    BANKSEL EEADR
    MOVF ee_address,W
    MOVWF EEADR
    BANKSEL EECON1
    BCF EECON1,7            ; EEPGD = 0 -> data EEPROM
    BSF EECON1,0            ; RD = 1 (data valid next cycle)
    BANKSEL EEDATA
    MOVF EEDATA,W
    MOVWF ee_data
    BCF ee_status,EEPROM_READ
    BANKSEL PORTA
    RETURN
 
; EEPROMWRITE
; In:  ee_address, ee_data
; Returns at once if EEPROM_WRITE or EEIF is set (ee_status unchanged).
; Returns without writing if the stored byte already equals ee_data
; (ee_data and any EEPROM_ERROR flag untouched).
; Otherwise starts the protected write, sets EEPROM_WRITE, and returns
; WITHOUT waiting. GIE is restored to its entry state.
EEPROMWrite:
    BTFSC ee_status,EEPROM_WRITE
    RETURN                  ; a write is already awaiting verification
    BANKSEL PIR2
    BTFSC PIR2,4
    RETURN                  ; EEIF set: previous write not yet verified
    
    ; ---- compare stored byte with ee_data (ee_data is NOT overwritten) ----
    BANKSEL EEADR
    MOVF ee_address,W
    MOVWF EEADR
    BANKSEL EECON1
    BCF EECON1,7            ; EEPGD = 0
    BSF EECON1,0            ; RD = 1
    BANKSEL EEDATA
    MOVF EEDATA,W
    XORWF ee_data,W         ; Z = 1 if stored byte == ee_data
    BTFSC STATUS,2
    goto WriteSkip          ; same value: no write, saves endurance
 
    ; ---- different value: set up the write (still Bank 2) ----
    MOVF ee_data,W
    XORLW 0x01             ; TEST ONLY: uncomment to program a WRONG byte and
                            ; force a verify failure (ee_data keeps the expected value)
    MOVWF EEDATA            ; data to write (EEADR already loaded)
    BANKSEL EECON1
    BSF EECON1,2            ; WREN = 1
    BSF ee_status,EEPROM_WRITE
 
    ; ---- save GIE, then disable it ----
    BCF ee_status,EEPROM_GIE
    BTFSC INTCON,7
    BSF ee_status,EEPROM_GIE
    
EEDisGIE:
    BCF INTCON,7            ; GIE = 0
    BTFSC INTCON,7          ; make sure it really cleared
    goto EEDisGIE
 
    ; ---- required unlock sequence: no other instructions in between ----
    MOVLW 0x55
    MOVWF EECON2
    MOVLW 0xAA
    MOVWF EECON2
    BSF EECON1,1            ; WR = 1 starts the write
    ; --------------------------------------------------------------------
 
    BTFSC ee_status,EEPROM_GIE
    BSF INTCON,7            ; restore GIE only if it was on at entry
    BCF ee_status,EEPROM_GIE
WriteSkip:
    BANKSEL PORTA
    RETURN
 
; EEPROMVERIFYWRITE - call after the hardware write finishes (EEIF = 1).
; In:  ee_address, ee_data (expected value, not overwritten)
; Match:    ee_status cleared (clears EEPROM_WRITE and any old EEPROM_ERROR).
; Mismatch: EEPROM_WRITE cleared, EEPROM_ERROR set. No retry.
; Always clears EEIF and WREN.
EEPROMVerifyWrite:
    BANKSEL EEADR
    MOVF ee_address,W
    MOVWF EEADR
    BANKSEL EECON1
    BCF EECON1,7            ; EEPGD = 0
    BSF EECON1,0            ; RD = 1
    BANKSEL EEDATA
    MOVF EEDATA,W
    XORWF ee_data,W         ; Z = 1 if match
    BTFSS STATUS,2
    goto VerifyFail
    CLRF ee_status          ; success: clear all status flags
    goto VerifyDone
VerifyFail:
    BCF ee_status,EEPROM_WRITE
    BSF ee_status,EEPROM_ERROR
VerifyDone:
    BANKSEL EECON1
    BCF EECON1,2            ; WREN = 0
    BANKSEL PIR2
    BCF PIR2,4              ; clear EEIF
    BANKSEL PORTA
    RETURN
End