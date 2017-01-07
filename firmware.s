#include p12lf1552.inc

; Reset vector
    org 0x0000
    goto init_pic

; Interrupt vector
    org 0x0004

    retfie

; Initialize PIC
; --------------
init_pic

    ; Clear interrupt register: disable all interrupts
    clrf INTCON


    ; Configure oscillator to 4MHz
    banksel OSCCON
    movlw 0x68
    movwf OSCCON

    ; Enable global interrupt
    banksel INTCON
    bsf INTCON, GIE

    end
