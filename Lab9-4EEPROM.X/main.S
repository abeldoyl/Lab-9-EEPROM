    ; Abel Doyle
    ; RCET3375
    ; Lab9-4EEPROM
    ; https://github.com/abeldoyl/Lab-9-EEPROM/tree/main/Lab9-4EEPROM.X
    
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
;   RA2 = PIN-error indicator (LED + resistor; ON only after an EEPROM
;         write/verify error, stays ON until power is cycled)
;   Put a pull-down (e.g. 10k) on RA0, RA1 and RA2 so they stay OFF while the
;   pins float during reset.
; ============================================================================
 BUZZER      EQU 0      ; PORTA bit
 SOLENOID    EQU 1      ; PORTA bit
 ERR_LED     EQU 2      ; PORTA bit
 
; ============================================================================
; EEPROM routine registers (same as Part 2, common RAM 0x70-0x7F)
; ============================================================================
 ee_address  EQU 0x70
 ee_data     EQU 0x71
 ee_status   EQU 0x72
 ee_want     EQU 0x73   ; used only inside EEPROMWrite / EEPROMVerifyWrite
 
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
 ;           EQU 0x29   ; (free, was pinCount in Part 3)
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
 mode        EQU 0x36   ; 0 = invalid PIN, 1 = normal locked, 2 = PIN change
 phase       EQU 0x37   ; PIN change mode: 0 = current PIN, 1 = new PIN x2
 pinBuf      EQU 0x38   ; 4 bytes 0x38-0x3B: current-PIN entry (digits 0-9)
 newBuf      EQU 0x3C   ; 8 bytes 0x3C-0x43: new PIN entry 1 then entry 2
 entryCnt    EQU 0x44   ; keys accepted so far in this entry (digits AND #)
 ptrIdx      EQU 0x45   ; index of next digit slot (# does not advance it)
 result      EQU 0x46   ; match routine result: 0 busy, 1 ok, 2 fail
 wrIdx       EQU 0x47   ; PINWrite step 0-5
 
; ---- SysFlags bits ----
 unlocked    EQU 0      ; 1 = solenoid output active
 PIN_UPDATE  EQU 1      ; 1 = PINWrite running (or stopped by an error)
 pinFault    EQU 2      ; 1 = EEPROM error: locked out until power cycle
 cWait       EQU 3      ; 1 = C pressed first, waiting for #
 
; ---- Constants ----
 ZFLAG        EQU 2
 CFLAG        EQU 0
 PIN_LENGTH   EQU 4
 ENTRY_BYTES  EQU 12     ; pinBuf + newBuf, cleared together
 DEBOUNCE_TICKS EQU 20   ; ~20 ms (tick = 1.024 ms)
 BUZZ_TICKS   EQU 150    ; ~154 ms
 UNLOCK_L     EQU 0xD1   ; 977 ticks = 0x03D1 = ~1.0 s
 UNLOCK_H     EQU 0x03
 
 ; ---- EEPROM map (five consecutive addresses) ----
 PIN_ADDR     EQU 0x10   ; PIN digits 1-4 at 0x10, 0x11, 0x12, 0x13
 MARKER_ADDR  EQU 0x14   ; PIN-valid marker
 MARKER_VALID EQU 0xC4   ; 0xC4 = PIN valid, anything else = invalid
 MARKER_CLEAR EQU 0x00   ; written first by PINWrite
 
 ; ---- Modes and results ----
 MODE_INVALID EQU 0
 MODE_LOCKED  EQU 1
 MODE_CHANGE  EQU 2
 RES_BUSY     EQU 0
 RES_OK       EQU 1
 RES_FAIL     EQU 2
 
 KEY_STAR     EQU 0x2A
 KEY_POUND    EQU 0x23
 KEY_C        EQU 0x43
 
; ---- Display status characters (ASCII) ----
 CH_LOCKED    EQU 0x4C   ; 'L' normal locked mode, enter current PIN
 CH_OPEN      EQU 0x55   ; 'U' unlocked (during the 1 s output)
 CH_NEW       EQU 0x4E   ; 'N' enter NEW PIN (invalid mode / change mode)
 CH_REPEAT    EQU 0x52   ; 'R' repeat the new PIN
 CH_CURRENT   EQU 0x50   ; 'P' enter CURRENT PIN (change mode)
 CH_SAVED     EQU 0x53   ; 'S' new PIN saved
 CH_FAIL      EQU 0x46   ; 'F' entry rejected / cancelled
 CH_EEERR     EQU 0x58   ; 'X' EEPROM write/verify error
 
PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup
 
PSECT code,class=CODE,delta=2
 
; ----------------------------------------------------------------------------
; SETUP - outputs are cleared BEFORE they are enabled, so the buzzer, solenoid
; and error outputs are LOW at startup. No interrupts; TMR0 free-runs as a
; ~1.024 ms tick (4 MHz, prescaler 1:4) that the loop polls.
; The PIN-valid marker selects the starting mode.
; ----------------------------------------------------------------------------
Setup:
    BANKSEL PORTA
    CLRF PORTA              ; buzzer, solenoid, error latches LOW first
    CLRF PORTB              ; row output latches LOW
    CLRF PORTC
 
    BANKSEL ANSEL
    CLRF ANSEL
    CLRF ANSELH
 
    BANKSEL TRISA
    MOVLW 0xF8
    MOVWF TRISA             ; RA0 buzzer, RA1 solenoid, RA2 error = outputs
    MOVLW 0xFE
    MOVWF TRISB             ; RB0 row output (low), RB1-RB7 inputs
    CLRF TRISC              ; DLG7137 data
    MOVLW 0xF0
    MOVWF WPUB              ; weak pull-ups on the column pins RB4-RB7
    MOVLW 0x01
    MOVWF OPTION_REG        ; RBPU = 0, TMR0 internal clock, prescaler 1:4
 
    BANKSEL EECON1
    BCF EECON1,7            ; EEPGD = 0 -> data EEPROM
    BCF EECON1,2            ; WREN = 0 (only EEPROMWrite turns it on)
 
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
    CLRF phase
    CLRF wrIdx
    CALL ClearEntry         ; no digits collected after reset
 
    MOVLW MARKER_ADDR       ; read the PIN-valid marker
    MOVWF ee_address
    CALL EEPROMRead
    CLRF mode               ; assume MODE_INVALID
    MOVLW MARKER_VALID
    XORWF ee_data,W
    BTFSC STATUS,ZFLAG
    INCF mode,F             ; marker = 0xC4 -> MODE_LOCKED
    CALL SetPrompt          ; 'N' or 'L'
 
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
;   Every press beeps (100-250 ms) in every mode.
;   After an EEPROM error (pinFault) or during the solenoid pulse the key
;   only beeps. Otherwise the key goes to the routine for the current mode.
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
 
    BTFSC SysFlags,pinFault
    RETURN                  ; EEPROM error: no more PIN attempts until reset
    BTFSC SysFlags,unlocked
    RETURN                  ; output active: no PIN entry
 
    MOVF entryCnt,F         ; first key of a new entry: show the prompt
    BTFSS STATUS,ZFLAG
    goto KeyDispatch
    BTFSC SysFlags,cWait
    goto KeyDispatch
    CALL SetPrompt
 
KeyDispatch:
    MOVF mode,F
    BTFSC STATUS,ZFLAG
    goto ModeInvalid
    DECF mode,W
    BTFSC STATUS,ZFLAG
    goto ModeLocked
    goto ModeChange
 
; ---- Invalid PIN mode: NewPINMatch, then save. Solenoid never activates. ----
ModeInvalid:
    CALL NewPINMatch
    MOVF result,W
    XORLW RES_OK
    BTFSC STATUS,ZFLAG
    goto InvSave
    MOVF result,W
    XORLW RES_FAIL
    BTFSS STATUS,ZFLAG
    RETURN                  ; still busy
    CALL ClearEntry         ; mismatch / * / unexpected key: restart, no save
    MOVLW CH_FAIL
    MOVWF dispChar
    RETURN
InvSave:
    CALL PINWrite
    goto SaveDone
 
; ---- Normal locked mode: PIN unlocks, C then # starts a PIN change. ----
ModeLocked:
    BTFSS SysFlags,cWait
    goto LockNoC
    BCF SysFlags,cWait      ; C was pressed first: this key must be #
    MOVF keyIn,W
    XORLW KEY_POUND
    BTFSS STATUS,ZFLAG
    goto LockFail           ; C not followed by #: back to locked
    MOVLW MODE_CHANGE
    MOVWF mode
    CLRF phase
    CALL ClearEntry
    CALL SetPrompt          ; 'P'
    RETURN
LockNoC:
    MOVF entryCnt,F
    BTFSS STATUS,ZFLAG
    goto LockPin            ; C is only special as the FIRST key
    MOVF keyIn,W
    XORLW KEY_C
    BTFSS STATUS,ZFLAG
    goto LockPin
    BSF SysFlags,cWait
    RETURN
LockPin:
    CALL CurrentPINMatch
    MOVF result,W
    XORLW RES_OK
    BTFSC STATUS,ZFLAG
    goto LockUnlock
    MOVF result,W
    XORLW RES_FAIL
    BTFSS STATUS,ZFLAG
    RETURN                  ; still busy
LockFail:
    CALL ClearEntry
    MOVLW CH_FAIL
    MOVWF dispChar
    RETURN
LockUnlock:
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
 
; ---- PIN change mode: CurrentPINMatch, then NewPINMatch, then save. ----
; Solenoid never activates here. Any failure returns to locked, old PIN kept.
ModeChange:
    MOVF phase,F
    BTFSS STATUS,ZFLAG
    goto ChgNew
    CALL CurrentPINMatch
    MOVF result,W
    XORLW RES_OK
    BTFSC STATUS,ZFLAG
    goto ChgAuthOk
    MOVF result,W
    XORLW RES_FAIL
    BTFSS STATUS,ZFLAG
    RETURN                  ; still busy
    goto ChgCancel
ChgAuthOk:
    MOVLW 1                 ; current PIN correct: ask for the new PIN
    MOVWF phase
    CALL ClearEntry
    CALL SetPrompt          ; 'N'
    RETURN
ChgNew:
    CALL NewPINMatch
    MOVF result,W
    XORLW RES_OK
    BTFSC STATUS,ZFLAG
    goto ChgSave
    MOVF result,W
    XORLW RES_FAIL
    BTFSS STATUS,ZFLAG
    RETURN                  ; still busy
ChgCancel:
    CALL ToLocked           ; cancelled / mismatch / wrong PIN: no EEPROM write
    MOVLW CH_FAIL
    MOVWF dispChar
    RETURN
ChgSave:
    CALL PINWrite
    goto SaveDone
 
; SAVEDONE - common end of a save (invalid mode and change mode).
; If PINWrite stopped with an error the error display is kept.
SaveDone:
    CALL ClearEntry         ; never leave PIN digits in RAM
    BTFSC SysFlags,pinFault
    RETURN                  ; error: stay locked out, 'X' and RA2 already set
    CALL ToLocked
    MOVLW CH_SAVED
    MOVWF dispChar
    RETURN
 
; TOLOCKED - go to normal locked mode with nothing half-entered.
ToLocked:
    MOVLW MODE_LOCKED
    MOVWF mode
    CLRF phase
    BCF SysFlags,cWait
    CALL ClearEntry
    RETURN
 
; SETPROMPT - show the prompt character for the current mode / phase.
;   mode 0: 'N'   mode 1: 'L'   mode 2: 'P' (phase 0) or 'N' (phase 1)
SetPrompt:
    MOVF mode,F
    BTFSC STATUS,ZFLAG
    goto PromptNew
    DECF mode,W
    BTFSC STATUS,ZFLAG
    goto PromptLocked
    MOVF phase,F
    BTFSS STATUS,ZFLAG
    goto PromptNew
    MOVLW CH_CURRENT
    MOVWF dispChar
    RETURN
PromptLocked:
    MOVLW CH_LOCKED
    MOVWF dispChar
    RETURN
PromptNew:
    MOVLW CH_NEW
    MOVWF dispChar
    RETURN
 
; CLEARENTRY - forget all collected digits (current and new buffers),
; the key count, the pointer and the result.
ClearEntry:
    CLRF entryCnt
    CLRF ptrIdx
    CLRF result
    MOVLW pinBuf
    MOVWF FSR
    MOVLW ENTRY_BYTES
    MOVWF loopCnt
ClrLoop:
    CLRF INDF
    INCF FSR,F
    DECFSZ loopCnt,F
    goto ClrLoop
    RETURN
 
; GETDIGIT - In: keyIn.  Out: digit = keyIn - '0', C = 1 if keyIn is 0-9.
GetDigit:
    MOVLW 0x30
    SUBWF keyIn,W           ; W = key - '0'
    MOVWF digit
    SUBLW 0x09              ; C = 1 if digit <= 9
    RETURN
 
; ----------------------------------------------------------------------------
; CURRENTPINMATCH - collects  d d d d #  one key per call (polled, so the
; keypad is never blocked).  In: keyIn.
;   Keys 1-4 : digit 0-9, stored at pinBuf[ptrIdx] through FSR/INDF, ptr++
;   Key 5    : must be #. Not stored, pointer not advanced. Then ComparePin
;              reads the stored PIN with EEPROMRead.
;   * or any unexpected key aborts.
; Out: result = RES_BUSY (need more keys), RES_OK (PIN matches),
;               RES_FAIL (aborted or no match).
; The caller decides what a match means (unlock, or authenticate a change).
; ----------------------------------------------------------------------------
CurrentPINMatch:
    MOVF keyIn,W
    XORLW KEY_STAR
    BTFSC STATUS,ZFLAG
    goto CurFail
    MOVF entryCnt,W
    XORLW PIN_LENGTH
    BTFSC STATUS,ZFLAG
    goto CurNeedPound       ; fifth key: must be #
    CALL GetDigit
    BTFSS STATUS,CFLAG
    goto CurFail            ; not 0-9
    MOVLW pinBuf
    ADDWF ptrIdx,W
    MOVWF FSR
    MOVF digit,W
    MOVWF INDF              ; pinBuf[ptrIdx] = digit
    INCF ptrIdx,F
    INCF entryCnt,F
    MOVLW RES_BUSY
    MOVWF result
    RETURN
CurNeedPound:
    MOVF keyIn,W
    XORLW KEY_POUND
    BTFSS STATUS,ZFLAG
    goto CurFail
    CALL ComparePin         ; Z = 1 if all four digits match EEPROM
    MOVLW RES_FAIL          ; (MOVLW does not change Z)
    BTFSC STATUS,ZFLAG
    MOVLW RES_OK
    MOVWF result
    RETURN
CurFail:
    MOVLW RES_FAIL
    MOVWF result
    RETURN
 
; COMPAREPIN - reads the stored PIN with EEPROMRead (PIN_ADDR..PIN_ADDR+3)
; and compares it with pinBuf. All four digits are always checked.
; Out: Z = 1 if they all match.
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
; NEWPINMATCH - collects  d d d d # d d d d #  one key per call.  In: keyIn.
;   entryCnt counts every accepted key (0-9). Key numbers 5 and 10
;   (entryCnt = 4 and 9 before the key) must be #. Digits go to
;   newBuf[ptrIdx]; # is not stored and does not advance ptrIdx.
;   * or any unexpected key aborts. After the final # the two groups of four
;   digits are compared in RAM. This routine never writes EEPROM.
; Out: result = RES_BUSY, RES_OK (both entries match), RES_FAIL.
; ----------------------------------------------------------------------------
NewPINMatch:
    MOVF keyIn,W
    XORLW KEY_STAR
    BTFSC STATUS,ZFLAG
    goto NewFail
    MOVF entryCnt,W
    XORLW 4
    BTFSC STATUS,ZFLAG
    goto NewNeedPound       ; fifth key
    MOVF entryCnt,W
    XORLW 9
    BTFSC STATUS,ZFLAG
    goto NewNeedPound       ; tenth key
    CALL GetDigit
    BTFSS STATUS,CFLAG
    goto NewFail            ; not 0-9
    MOVLW newBuf
    ADDWF ptrIdx,W
    MOVWF FSR
    MOVF digit,W
    MOVWF INDF              ; newBuf[ptrIdx] = digit
    INCF ptrIdx,F
    INCF entryCnt,F
    MOVLW RES_BUSY
    MOVWF result
    RETURN
NewNeedPound:
    MOVF keyIn,W
    XORLW KEY_POUND
    BTFSS STATUS,ZFLAG
    goto NewFail
    INCF entryCnt,F         ; # counts as a key but is not stored
    MOVF entryCnt,W
    XORLW 10
    BTFSC STATUS,ZFLAG
    goto NewCompare         ; second # received
    MOVLW CH_REPEAT         ; first # received: ask for the PIN again
    MOVWF dispChar
    MOVLW RES_BUSY
    MOVWF result
    RETURN
NewCompare:
    CLRF mismatch
    CLRF cmpIdx
NcLoop:
    MOVLW newBuf
    ADDWF cmpIdx,W
    MOVWF FSR
    MOVF INDF,W             ; digit from entry 1
    MOVWF tmp
    MOVLW PIN_LENGTH
    ADDWF FSR,F             ; same digit position in entry 2
    MOVF INDF,W
    XORWF tmp,W             ; 0 if equal
    IORWF mismatch,F
    INCF cmpIdx,F
    MOVF cmpIdx,W
    XORLW PIN_LENGTH
    BTFSS STATUS,ZFLAG
    goto NcLoop
    MOVF mismatch,F         ; Z = 1 only if every digit matched
    MOVLW RES_FAIL
    BTFSC STATUS,ZFLAG
    MOVLW RES_OK
    MOVWF result
    RETURN
NewFail:
    MOVLW RES_FAIL
    MOVWF result
    RETURN
 
; ----------------------------------------------------------------------------
; PINWRITE - saves newBuf[0..3] as the new PIN with six EEPROM steps:
;   0: marker = 0x00     1-4: PIN digits 1-4     5: marker = 0xC4
; Called only after NewPINMatch succeeded (and CurrentPINMatch, for a change).
; Blocks everything else on purpose: no tick, no keypad, no unlock.
; Each step: EEPROMWrite, wait for WR = 0, EEPROMVerifyWrite, check
; EEPROM_ERROR. On an error the sequence stops, the solenoid stays OFF, RA2
; goes HIGH, 'X' is shown and pinFault locks out all PIN entry until reset.
; ----------------------------------------------------------------------------
PINWrite:
    BSF SysFlags,PIN_UPDATE
    BCF PORTA,SOLENOID      ; solenoid OFF while the PIN is being written
    CLRF wrIdx
PwLoop:
    MOVF wrIdx,F
    BTFSC STATUS,ZFLAG
    goto PwMarkClear        ; step 0
    MOVF wrIdx,W
    XORLW 5
    BTFSC STATUS,ZFLAG
    goto PwMarkValid        ; step 5
    MOVLW PIN_ADDR-1        ; steps 1-4: digit wrIdx
    ADDWF wrIdx,W
    MOVWF ee_address
    MOVLW newBuf-1
    ADDWF wrIdx,W
    MOVWF FSR
    MOVF INDF,W
    MOVWF ee_data
    goto PwStep
PwMarkClear:
    MOVLW MARKER_ADDR
    MOVWF ee_address
    MOVLW MARKER_CLEAR
    MOVWF ee_data
    goto PwStep
PwMarkValid:
    MOVLW MARKER_ADDR
    MOVWF ee_address
    MOVLW MARKER_VALID
    MOVWF ee_data
PwStep:
    CALL EEPROMWrite        ; starts the write (skips a byte already correct)
PwWait:
    BANKSEL EECON1
    BTFSC EECON1,1          ; WR = 1 while the write is running
    goto PwWait
    BANKSEL PORTA
    CALL EEPROMVerifyWrite  ; read back and compare
    BTFSC ee_status,EEPROM_ERROR
    goto PwFail
    INCF wrIdx,F
    MOVF wrIdx,W
    XORLW 6
    BTFSS STATUS,ZFLAG
    goto PwLoop
    BCF SysFlags,PIN_UPDATE ; step 6 verified: done
    BCF INTCON,2            ; drop the tick that piled up during the write
    CLRF keyEvent
    RETURN
PwFail:
    BSF SysFlags,pinFault   ; stop: no remaining bytes are written
    BCF PORTA,SOLENOID
    BSF PORTA,ERR_LED       ; PIN-error indicator
    MOVLW CH_EEERR
    MOVWF dispChar
    BCF INTCON,2
    CLRF keyEvent
    RETURN                  ; PIN_UPDATE stays set; only a reset clears it
 
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
 
; ============================================================================
; EEPROMWRITE - Part 2 routine, interface unchanged
; In:  ee_address, ee_data
; Returns at once if EEPROM_WRITE or EEIF is set (ee_status unchanged).
; Returns without writing if the stored byte already equals ee_data
; (ee_data and any EEPROM_ERROR flag untouched).
; Otherwise starts the protected write, sets EEPROM_WRITE, and returns
; WITHOUT waiting. GIE is restored to its entry state.
; ============================================================================
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
    ;XORLW 0x01             ; TEST ONLY: uncomment to program a WRONG byte and
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
 
; ============================================================================
; EEPROMVERIFYWRITE - Part 2 routine, interface unchanged
; Call after the hardware write finishes (EEIF = 1).
; In:  ee_address, ee_data (expected value, not overwritten)
; Match:    ee_status cleared (clears EEPROM_WRITE and any old EEPROM_ERROR).
; Mismatch: EEPROM_WRITE cleared, EEPROM_ERROR set. No retry.
; Always clears EEIF and WREN.
; ============================================================================
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