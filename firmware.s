#include p12lf1552.inc

; 7-bit slave address on bits [7-1], hence 0x15
#define I2C_ADDRESS (0x3A)


; Reset vector
    org 0x0000
    goto init_pic

; Interrupt vector
    org 0x0004

    banksel PIR1
    btfsc PIR1, SSP1IF
    call handle_i2c_interrupt

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

    ; Configure I2C
    banksel APFCON
    bsf APFCON, SDSEL   ; SDA function is on RA3

    banksel SSPADD
    movlw I2C_ADDRESS   ; Set 7-bit address
    movwf SSPADD
    movlw 0xFE
    movwf SSPMSK

    clrf SSPCON3
    movlw 0x01          ; Enable clock stretching
    movwf SSPCON2
    movlw 0x26          ; Configure module in I2C 7-bit slave mode
    movwf SSPCON1       ; and configure gpios

    banksel PIR1        ; Enable I2C interrupts
    bcf PIR1, SSP1IF
    banksel PIE1
    bsf PIE1, SSP1IE
    banksel INTCON
    bsf INTCON, PEIE

    ; Enable global interrupt
    banksel INTCON
    bsf INTCON, GIE

loop
    goto loop

handle_i2c_interrupt
    bcf PIR1, SSP1IF

    banksel SSPBUF
    movf SSPBUF, W          ; Read buffer

    btfss SSPSTAT, R_NOT_W
    call handle_i2c_write
    btfsc SSPSTAT, R_NOT_W
    call handle_i2c_read

    banksel SSPCON2
    btfsc SSPCON2, SEN      ; Release clock if clock stretching is enabled
    bsf SSPCON1, CKP

    return

handle_i2c_write
    ; For now, ignore any write
    return

handle_i2c_read
    ; For now, just send 0
    clrf SSPBUF
    return

    end
