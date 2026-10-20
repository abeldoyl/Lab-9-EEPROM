    ; Abel Doyle
    ; RCET3373
    ; Lab2-4PIC
    ; https://github.com/abeldoyl/Lab-02-PIC-I-O/tree/main/Lab2-4PIC/Lab2-4PIC.X
    
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

; Reset Vector at 0000h. Execution starts here after reset.
PSECT resetVect,class=CODE,delta=2
ResetVector: 
    goto Setup


; Main code section starts at 0008h. User code goes here.
PSECT code,class=CODE,delta=2
 
Setup:
    ; add device setup here
    ; Bank 0
    BANKSEL PORTB	;Select PORTB
    CLRF PORTB		;Clearing all previous data on PORTB
    BANKSEL PORTC	;Select PORTC
    CLRF PORTC		;Clearing all previous data on PORTC
    
    ; Bank 1
    BANKSEL TRISB	;Select TRISB
    MOVLW 0xFE		;start with Row1 output, everything else input
    MOVWF TRISB		;"
    BANKSEL TRISC	;Select TRISC
    CLRF TRISC		;makes PORTC an output
    BANKSEL WPUB	;Select WPUB
    MOVLW 0xF0		;Weak pull-ups on RB4-RB7 (the four column inputs)
    MOVWF WPUB		;"
    BANKSEL OPTION_REG	;Select OPTION_REG
    BCF OPTION_REG,7	;RBPU = 0 -> enable PORTB weak pull-ups globally
    
    ; Bank 3
    BANKSEL ANSELH     ;Select ANSELH
    CLRF ANSELH        ;PORTB pins used here are set to be digital, not analog
    
    goto Main
    
Main:
    ; main code goes here
    CLRF 0x20		;Clear register low key is set low
    CLRF 0x21		;Clear register high key is set low
	
	;Scan for data on Row 1 (Pin8 & RB0) 
	BCF 0x03,6	;Set Bank 1
	BSF 0x03,5	;"
	MOVLW 0xFE	;Set the RB0 output is low, RB1-RB7 input
	MOVWF 0x86	;Send W to PortB
        BCF 0x03,6	;Set Bank 0
        BCF 0x03,5	;"
	BTFSS 0x06,4	;Check Pin 4 for 1
        BSF 0x20,1
        BTFSS 0x06,5    ;Check Pin 3 for 2
        BSF 0x20,2
        BTFSS 0x06,6    ;Check Pin 2 for 3
        BSF 0x20,3 
        BTFSS 0x06,7    ;Check Pin 1 for A
        BSF 0x21,2
	
	;Scan for data on Row 2 (Pin7 & RB1)
	BCF 0x03,6      ;Set Bank 1
        BSF 0x03,5      ;"
        MOVLW 0xFD      ;Set the RB1 output-low, rest input
        MOVWF 0x86      ;Send W to PortB
        BCF 0x03,6      ;Set Bank 0
        BCF 0x03,5      ;"
        BTFSS 0x06,4    ;Check Pin 4 for 4
        BSF 0x20,4
        BTFSS 0x06,5    ;Check Pin 3 for 5
        BSF 0x20,5
        BTFSS 0x06,6    ;Check Pin 2 for 6
        BSF 0x20,6
        BTFSS 0x06,7    ;Check Pin 1 for B
        BSF 0x21,3
	
	;Scan for data on Row 3 (Pin6 & RB2)
	BCF 0x03,6      ;Set Bank 1
        BSF 0x03,5      ;"
        MOVLW 0xFB      ;Set the RB2 output-low, rest input
        MOVWF 0x86      ;Send W to PortB
        BCF 0x03,6      ;Set Bank 0
        BCF 0x03,5      ;"
        BTFSS 0x06,4    ;Check Pin 4 for 7
        BSF 0x20,7
        BTFSS 0x06,5    ;Check Pin 3 for 8
        BSF 0x21,0
        BTFSS 0x06,6    ;Check Pin 2 for 9
        BSF 0x21,1
        BTFSS 0x06,7    ;Check Pin 1 for C
        BSF 0x21,4
	
	;Scan for data on Row 4 (Pin6 & RB3)
	BCF 0x03,6      ;Set Bank 1
        BSF 0x03,5      ;"
        MOVLW 0xF7      ;Set the RB3 output-low, rest input
        MOVWF 0x86      ;Send W to PortB
        BCF 0x03,6      ;Set Bank 0
        BCF 0x03,5      ;"
        BTFSS 0x06,4    ;Check Pin 4 for *
        BSF 0x21,6
        BTFSS 0x06,5    ;Check Pin 3 for 0
        BSF 0x20,0
        BTFSS 0x06,6    ;Check Pin 2 for #
        BSF 0x21,7
        BTFSS 0x06,7    ;Check Pin 1 for D
        BSF 0x21,5
	
    BANKSEL PORTB
    goto PriorityEncode
    
    PriorityEncode:
    
    BTFSS   0x21,7      ;Test for if # is pressed
    goto    TestStar
    goto    DisplayPound
    
    TestStar:
    BTFSS   0x21,6      ;Test for if * is pressed
    goto    TestD
    goto    DisplayStar
    
    TestD:
    BTFSS   0x21,5      ;Test for if D is pressed
    goto    TestC
    goto    DisplayD
    
    TestC:
    BTFSS   0x21,4      ;Test for if C is pressed
    goto    TestB
    goto    DisplayC
    
    TestB:
    BTFSS   0x21,3      ;Test for if B is pressed
    goto    TestA
    goto    DisplayB
    
    TestA:
    BTFSS   0x21,2      ;Test for if A is pressed
    goto    Test9
    goto    DisplayA
    
    Test9:
    BTFSS   0x21,1      ;Test for if 9 is pressed
    goto    Test8
    goto    Display9
    
    Test8:
    BTFSS   0x21,0      ;Test for if 8 is pressed
    goto    Test7
    goto    Display8
    
    Test7:
    BTFSS   0x20,7      ;Test for if 7 is pressed
    goto    Test6
    goto    Display7
    
    Test6:
    BTFSS   0x20,6      ;Test for if 6 is pressed
    goto    Test5
    goto    Display6
    
    Test5:
    BTFSS   0x20,5      ;Test for if 5 is pressed
    goto    Test4
    goto    Display5
    
    Test4:
    BTFSS   0x20,4      ;Test for if 4 is pressed
    goto    Test3
    goto    Display4
    
    Test3:
    BTFSS   0x20,3      ;Test for if 3 is pressed
    goto    Test2
    goto    Display3
    
    Test2:
    BTFSS   0x20,2      ;Test for if 2 is pressed
    goto    Test1
    goto    Display2
    
    Test1:
    BTFSS   0x20,1      ;Test for if 1 is pressed 
    goto    Test0
    goto    Display1
    
    Test0:
    BTFSS   0x20,0      ;Test for if 0 is pressed
    goto    DisplayDefault
    goto    Display0

    
    Display9:
    MOVLW 0x39      ;Select the character set for display 9
    MOVWF 0x07      ;Send W to PortC
    goto Main

    Display8:
    MOVLW 0x38      ;Select the character set for display 8
    MOVWF 0x07      ;Send W to PortC
    goto Main

    Display7:
    MOVLW 0x37      ;Select the character set for display 7
    MOVWF 0x07      ;Send W to PortC
    goto Main

    Display6:
    MOVLW 0x36      ;Select the character set for display 6
    MOVWF 0x07      ;Send W to PortC
    goto Main

    Display5:
    MOVLW 0x35      ;Select the character set for display 5
    MOVWF 0x07      ;Send W to PortC
    goto Main

    Display4:
    MOVLW 0x34      ;Select the character set for display 4
    MOVWF 0x07      ;Send W to PortC
    goto Main

    Display3:
    MOVLW 0x33      ;Select the character set for display 3
    MOVWF 0x07      ;Send W to PortC
    goto Main

    Display2:
    MOVLW 0x32      ;Select the character set for display 2
    MOVWF 0x07      ;Send W to PortC
    goto Main

    Display1:
    MOVLW 0x31      ;Select the character set for display 1
    MOVWF 0x07      ;Send W to PortC
    goto Main

    Display0:
    MOVLW 0x30      ;Select the character set for display 0
    MOVWF 0x07      ;Send W to PortC
    goto Main

    DisplayA:
    MOVLW 0x41      ;Select the character set for display A
    MOVWF 0x07      ;Send W to PortC
    goto Main

    DisplayB:
    MOVLW 0x42      ;Select the character set for display B
    MOVWF 0x07      ;Send W to PortC
    goto Main

    DisplayC:
    MOVLW 0x43      ;Select the character set for display C
    MOVWF 0x07      ;Send W to PortC
    goto Main

    DisplayD:
    MOVLW 0x44      ;Select the character set for display D
    MOVWF 0x07      ;Send W to PortC
    goto Main

    DisplayStar:
    MOVLW 0x2A      ;Select the character set for display *
    MOVWF 0x07      ;Send W to PortC
    goto Main

    DisplayPound:
    MOVLW 0x23      ;Select the character set for display #
    MOVWF 0x07      ;Send W to PortC
    goto Main

    DisplayDefault:
    MOVLW 0x24      ;Select the character set for display $
    MOVWF 0x07      ;Send W to PortC
    goto Main
End
    