    ; Abel Doyle
    ; RCET3375
    ; Lab9-3EEPROM
    ; https://github.com/abeldoyl/Lab-9-EEPROM/tree/main/Lab9-3EEPROM.X
    
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
; PIN MAP
;   PORTB RB0-RB3 = keypad rows (driven low one at a time via TRISB)
;   PORTB RB4-RB7 = keypad columns (inputs, weak pull-ups)
;   PORTC RC0-RC6 = DLG7137 D0-D6 (ASCII)
;   RA0 = active buzzer (through a transistor driver)
;   RA1 = simulated solenoid output (LED / driver, NOT a real solenoid)
;   Put a pull-down (e.g. 10k) on RA0 and RA1 so they stay OFF while the pins
;   float during reset.
; ============================================================================
 BUZZER      EQU 0      ; PORTA bit
 SOLENOID    EQU 1      ; PORTA bit
 
; ============================================================================
; EEPROM routine registers (same as Part 2, common RAM 0x70-0x7F)
; ============================================================================
 ee_address  EQU 0x70
 ee_data     EQU 0x71
 ee_status   EQU 0x72
 
 EEPROM_READ  EQU 0
 EEPROM_WRITE EQU 1
 EEPROM_ERROR EQU 2
 EEPROM_GIE   EQU 7
 
; ============================================================================
; Application variables (Bank 0)
; ============================================================================
 SysFlags    EQU 0x20   ; bit flags (below)
 keyChar     EQU 0x21   ; result of one keypad scan: ASCII, or 0 = none/invalid
 keyCount    EQU 0x22   ; number of keys seen in one scan
 keyCand     EQU 0x23   ; candidate key being debounced
 keyStable   EQU 0x24   ; debounced key level (0 = no key)
 keyCnt      EQU 0x25   ; debounce tick counter
 keyEvent    EQU 0x26   ; debounced press event (ASCII), 0 = none
 keyIn       EQU 0x27   ; key being processed
 digit       EQU 0x28   ; numeric value of a digit key (0-9)
 pinCount    EQU 0x29   ; digits collected so far
 dispChar    EQU 0x2A   ; character shown on the DLG7137
 buzzCnt     EQU 0x2B   ; buzzer countdown (ticks)
 unlkL       EQU 0x2C   ; solenoid pulse countdown, low byte
 unlkH       EQU 0x2D   ; solenoid pulse countdown, high byte
 scanRow     EQU 0x2E
 scanCol     EQU 0x2F
 scanCols    EQU 0x30
 rowMask     EQU 0x31
 tmp         EQU 0x32
 mismatch    EQU 0x33   ; OR of all digit differences during compare
 cmpIdx      EQU 0x34
 loopCnt     EQU 0x35
 pinBuf      EQU 0x38   ; 4 bytes: 0x38-0x3B (entered digits, values 0-9)
 
; ---- SysFlags bits ----
 unlocked    EQU 0      ; 1 = solenoid output active
 entryBad    EQU 1      ; 1 = fifth digit pressed, entry already rejected
 
; ---- Constants ----
 ZFLAG        EQU 2
 CFLAG        EQU 0
 PIN_LENGTH   EQU 4
 PIN_ADDR     EQU 0x10   ; PIN stored at EEPROM 0x10-0x13 (programmed by hand)
 DEBOUNCE_TICKS EQU 20   ; ~20 ms (tick = 1.024 ms)
 BUZZ_TICKS   EQU 150    ; ~154 ms
 UNLOCK_L     EQU 0xD1   ; 977 ticks = 0x03D1 = ~1.0 s
 UNLOCK_H     EQU 0x03
 
 KEY_STAR     EQU 0x2A
 KEY_POUND    EQU 0x23
 
; ---- Display status characters (ASCII) ----
 CH_LOCKED    EQU 0x4C   ; 'L' locked, waiting for entry
 CH_ERROR     EQU 0x45   ; 'E' rejected (wrong PIN, too short, fifth digit)
 CH_CANCEL    EQU 0x43   ; 'C' entry cancelled with *
 CH_OPEN      EQU 0x55   ; 'U' unlocked (during the 1 s output)
                         ; '1'-'4' (0x31-0x34) = number of digits entered
 
PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup
 
PSECT code,class=CODE,delta=2
 
; ----------------------------------------------------------------------------
; SETUP - outputs are cleared BEFORE they are enabled, so the buzzer and
; solenoid outputs are LOW at startup. No interrupts; TMR0 free-runs as a
; ~1.024 ms tick (4 MHz, prescaler 1:4) that the loop polls.
; ----------------------------------------------------------------------------
Setup:
    BANKSEL PORTA
    CLRF PORTA              ; buzzer and solenoid latches LOW first
    CLRF PORTB              ; row output latches LOW
    CLRF PORTC
 
    BANKSEL ANSEL
    CLRF ANSEL
    CLRF ANSELH
 
    BANKSEL TRISA
    MOVLW 0xFC
    MOVWF TRISA             ; RA0 buzzer, RA1 solenoid = outputs
    MOVLW 0xFE
    MOVWF TRISB             ; RB0 row output (low), RB1-RB7 inputs
    CLRF TRISC              ; DLG7137 data
    MOVLW 0xF0
    MOVWF WPUB              ; weak pull-ups on the column pins RB4-RB7
    MOVLW 0x01
    MOVWF OPTION_REG        ; RBPU = 0, TMR0 internal clock, prescaler 1:4
 
    BANKSEL EECON1
    BCF EECON1,7            ; EEPGD = 0 -> data EEPROM
    BCF EECON1,2            ; WREN = 0 (this lab never writes)
 
    BANKSEL PORTA
    CLRF INTCON
    BCF STATUS,7            ; IRP = 0 (indirect access to Bank 0/1)
 
    CLRF SysFlags
    CLRF keyChar
    CLRF keyCount
    CLRF keyCand
    CLRF keyStable
    CLRF keyCnt
    CLRF keyEvent
    CLRF keyIn
    CLRF digit
    CLRF buzzCnt
    CLRF unlkL
    CLRF unlkH
    CLRF ee_address
    CLRF ee_data
    CLRF ee_status
    CALL ClearEntry         ; no digits collected after reset
    MOVLW CH_LOCKED
    MOVWF dispChar
 
MainLoop:
    CALL ServiceTick
    CALL ServiceKeys
    CALL ServiceDisplay
    goto MainLoop
 
; ----------------------------------------------------------------------------
; SERVICE TICK - once per TMR0 overflow (~1.024 ms):
;   buzzer countdown, solenoid pulse countdown, keypad scan + debounce.
; ----------------------------------------------------------------------------
ServiceTick:
    BTFSS INTCON,2
    RETURN
    BCF INTCON,2
 
    ; ---- buzzer countdown ----
    MOVF buzzCnt,F
    BTFSC STATUS,ZFLAG
    goto TickUnlock
    DECFSZ buzzCnt,F
    goto TickUnlock
    BCF PORTA,BUZZER        ; reached zero: buzzer OFF
 
    ; ---- 1 s solenoid pulse countdown (16-bit) ----
TickUnlock:
    BTFSS SysFlags,unlocked
    goto TickKeys
    MOVF unlkL,F
    BTFSC STATUS,ZFLAG
    DECF unlkH,F            ; borrow when low byte is 0
    DECF unlkL,F
    MOVF unlkL,W
    IORWF unlkH,W
    BTFSS STATUS,ZFLAG
    goto TickKeys
    BCF PORTA,SOLENOID      ; pulse finished: output LOW
    BCF SysFlags,unlocked
    MOVLW CH_LOCKED
    MOVWF dispChar
 
    ; ---- keypad debounce ----
    ; A key (or "no key") must be seen unchanged for DEBOUNCE_TICKS ticks
    ; before it becomes the stable level. Only a new non-zero stable level
    ; raises a press event, so one physical press = one event.
TickKeys:
    CALL ScanKeypad         ; keyChar = ASCII of the single pressed key, else 0
    MOVF keyChar,W
    XORWF keyCand,W
    BTFSC STATUS,ZFLAG
    goto CandSame
    MOVF keyChar,W          ; changed: restart the debounce
    MOVWF keyCand
    CLRF keyCnt
    RETURN
CandSame:
    MOVF keyCand,W
    XORWF keyStable,W
    BTFSC STATUS,ZFLAG
    RETURN                  ; already the stable level
    INCF keyCnt,F
    MOVLW DEBOUNCE_TICKS
    XORWF keyCnt,W
    BTFSS STATUS,ZFLAG
    RETURN
    CLRF keyCnt
    MOVF keyCand,W
    MOVWF keyStable         ; accept the new level
    MOVF keyStable,F
    BTFSC STATUS,ZFLAG
    RETURN                  ; release: no event
    MOVF keyStable,W
    MOVWF keyEvent          ; debounced press event
    RETURN
 
; ----------------------------------------------------------------------------
; SCAN KEYPAD - drives each row low in turn, reads the columns.
; Out: keyChar = ASCII of the key if EXACTLY ONE key is down, else 0.
; (Ignoring multi-key scans avoids ghost keys from simultaneous presses.)
; ----------------------------------------------------------------------------
ScanKeypad:
    CLRF keyChar
    CLRF keyCount
    CLRF scanRow
    MOVLW 0xFE
    MOVWF rowMask
RowLoop:
    MOVF rowMask,W          ; load W while still in Bank 0
    BANKSEL TRISB
    MOVWF TRISB             ; one row output-low, the rest inputs
    BANKSEL PORTB
    NOP                     ; let the column lines settle
    NOP
    SWAPF PORTB,W           ; RB7..RB4 -> bits 3..0
    XORLW 0x0F              ; 1 = pressed
    ANDLW 0x0F
    MOVWF scanCols
    BTFSC STATUS,ZFLAG
    goto NextRow            ; nothing pressed in this row
    CLRF scanCol
ColLoop:
    RRF scanCols,F          ; bit 0 -> carry
    BTFSS STATUS,CFLAG
    goto NextCol
    INCF keyCount,F
    CALL KeyToChar          ; W = ASCII for (scanRow, scanCol)
    MOVWF keyChar
NextCol:
    INCF scanCol,F
    MOVF scanCol,W
    XORLW 4
    BTFSS STATUS,ZFLAG
    goto ColLoop
NextRow:
    BSF STATUS,CFLAG        ; shift a 1 in so idle rows stay inputs
    RLF rowMask,F           ; 0xFE -> 0xFD -> 0xFB -> 0xF7
    INCF scanRow,F
    MOVF scanRow,W
    XORLW 4
    BTFSS STATUS,ZFLAG
    goto RowLoop
 
    DECF keyCount,W         ; Z = 1 if exactly one key was down
    BTFSS STATUS,ZFLAG
    CLRF keyChar            ; none or several keys: report no key
    RETURN
 
; KEYTOCHAR - keypad layout:  1 2 3 A / 4 5 6 B / 7 8 9 C / * 0 # D
; In: scanRow, scanCol (0-3).  Out: W = ASCII.
KeyToChar:
    MOVF scanCol,W
    XORLW 3
    BTFSC STATUS,ZFLAG
    goto KeyLetter          ; column 3 = A,B,C,D
    MOVF scanRow,W
    XORLW 3
    BTFSC STATUS,ZFLAG
    goto KeyBottom          ; row 3 = *,0,#
    MOVF scanRow,W
    MOVWF tmp
    ADDWF tmp,W             ; 2 x row
    ADDWF scanRow,W         ; 3 x row
    ADDWF scanCol,W         ; 3 x row + col
    ADDLW 0x31              ; + '1'
    RETURN
KeyLetter:
    MOVF scanRow,W
    ADDLW 0x41              ; 'A' + row
    RETURN
KeyBottom:
    MOVF scanCol,F
    BTFSC STATUS,ZFLAG
    RETLW KEY_STAR
    DECF scanCol,W
    BTFSC STATUS,ZFLAG
    RETLW 0x30              ; '0'
    RETLW KEY_POUND
 
; ----------------------------------------------------------------------------
; SERVICE KEYS - handles one debounced press event.
;   Every press beeps (100-250 ms), regardless of PIN result.
;   While the solenoid output is active, PIN actions are ignored.
;   0-9 add a digit, * cancels, # submits, A-D do nothing.
; ----------------------------------------------------------------------------
ServiceKeys:
    MOVF keyEvent,F
    BTFSC STATUS,ZFLAG
    RETURN
    MOVF keyEvent,W
    MOVWF keyIn
    CLRF keyEvent
 
    BSF PORTA,BUZZER        ; keypress beep (turned off by ServiceTick)
    MOVLW BUZZ_TICKS
    MOVWF buzzCnt
 
    BTFSC SysFlags,unlocked
    RETURN                  ; output active: no PIN entry
 
    MOVF keyIn,W
    XORLW KEY_STAR
    BTFSC STATUS,ZFLAG
    goto DoCancel
    MOVF keyIn,W
    XORLW KEY_POUND
    BTFSC STATUS,ZFLAG
    goto DoSubmit
 
    MOVLW 0x30
    SUBWF keyIn,W           ; W = key - '0'
    MOVWF digit
    SUBLW 0x09              ; C = 1 if digit <= 9
    BTFSS STATUS,CFLAG
    RETURN                  ; A-D: no PIN-entry action
    goto DoDigit
 
DoDigit:
    BTFSC SysFlags,entryBad
    RETURN                  ; already rejected: wait for # or *
    MOVF pinCount,W
    XORLW PIN_LENGTH
    BTFSC STATUS,ZFLAG
    goto DigitOverflow      ; this is a fifth digit
    MOVLW pinBuf
    ADDWF pinCount,W
    MOVWF FSR
    MOVF digit,W
    MOVWF INDF              ; pinBuf[pinCount] = digit
    INCF pinCount,F
    MOVLW 0x30
    ADDWF pinCount,W        ; show how many digits so far: '1'..'4'
    MOVWF dispChar
    RETURN
DigitOverflow:
    BSF SysFlags,entryBad   ; entry is now invalid, even if # follows
    MOVLW CH_ERROR
    MOVWF dispChar
    RETURN
 
DoCancel:
    CALL ClearEntry
    MOVLW CH_CANCEL
    MOVWF dispChar
    RETURN
 
DoSubmit:
    BTFSC SysFlags,entryBad
    goto Reject             ; had a fifth digit
    MOVF pinCount,W
    XORLW PIN_LENGTH
    BTFSS STATUS,ZFLAG
    goto Reject             ; fewer than four digits
    CALL ComparePin         ; Z = 1 if all four digits match EEPROM
    BTFSS STATUS,ZFLAG
    goto Reject
    CALL ClearEntry         ; correct: clear entry, start the 1 s pulse
    BSF PORTA,SOLENOID
    BSF SysFlags,unlocked
    MOVLW UNLOCK_L
    MOVWF unlkL
    MOVLW UNLOCK_H
    MOVWF unlkH
    MOVLW CH_OPEN
    MOVWF dispChar
    RETURN
Reject:
    CALL ClearEntry
    MOVLW CH_ERROR
    MOVWF dispChar
    RETURN
 
; CLEARENTRY - forget all collected digits and the "too long" flag.
ClearEntry:
    CLRF pinCount
    BCF SysFlags,entryBad
    MOVLW pinBuf
    MOVWF FSR
    MOVLW PIN_LENGTH
    MOVWF loopCnt
ClrLoop:
    CLRF INDF
    INCF FSR,F
    DECFSZ loopCnt,F
    goto ClrLoop
    RETURN
 
; COMPAREPIN - reads the stored PIN with EEPROMRead (PIN_ADDR..PIN_ADDR+3)
; and compares it with the entered digits. All four digits are always
; checked. Out: Z = 1 if they all match.
ComparePin:
    CLRF mismatch
    CLRF cmpIdx
CmpLoop:
    MOVLW PIN_ADDR
    ADDWF cmpIdx,W
    MOVWF ee_address
    CALL EEPROMRead         ; ee_data = stored digit
    MOVLW pinBuf
    ADDWF cmpIdx,W
    MOVWF FSR
    MOVF INDF,W             ; entered digit
    XORWF ee_data,W         ; 0 if equal
    IORWF mismatch,F
    INCF cmpIdx,F
    MOVF cmpIdx,W
    XORLW PIN_LENGTH
    BTFSS STATUS,ZFLAG
    goto CmpLoop
    MOVF mismatch,F         ; Z = 1 only if every digit matched
    RETURN
 
; ----------------------------------------------------------------------------
; SERVICE DISPLAY - DLG7137 on PORTC shows the one-character status.
; ----------------------------------------------------------------------------
ServiceDisplay:
    MOVF dispChar,W
    MOVWF PORTC
    RETURN 
    
; ============================================================================
; EEPROMREAD - unchanged from Part 2
; In:  ee_address = address to read
; Out: ee_data = byte read. Returns in Bank 0.
; ============================================================================
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
End