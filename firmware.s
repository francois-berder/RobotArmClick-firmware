#include p12lf1552.inc

; Configuration bits
;
; Configuration word 1:
; CLKOUTEN:     Disabled
; BOREN:        Enabled
; CP:           Disabled
; MCLRE:        Disabled
; PWRTE:        Enabled
; WDTE:         Disabled
; FOSC:         INTOSC
;
; Configuration word 2:
; LVP:          Disabled
; LPBOR:        Disabled
; BORV:         Low
; STVREN:       Enabled
; WRT:          All protected

    __CONFIG _CONFIG1, _CLKOUTEN_OFF & _BOREN_ON & _CP_OFF & _MCLRE_OFF & _PWRTE_ON & _WDTE_OFF & _FOSC_INTOSC
    __CONFIG _CONFIG2, _LVP_OFF & _LPBOR_OFF & _BORV_LO & _STVREN_ON & _WRT_ALL


; 7-bit slave address on bits [7-1], hence 0x15
#define I2C_ADDRESS (0x3A)

;   MEMORY MAP
;
;       name        |       address
;-----------------------------------
;    servo_con_0    |       0x20 (bank 0)
;    servo_con_1    |       0x21 (bank 0)
;    servo_con_2    |       0x22 (bank 0)
;    servo_con_3    |       0x23 (bank 0)
;    i2c_state      |       0x70 (shared)
;    i2c_buffer     |       0x71 (shared)
;    current_reg    |       0x72 (shared)

;   Each servo_con_X variable has this format:
;    ---------------------------------------
;   | D6 | D5 | D4 | D3 | D2 | D1 | D0 | EN |
;    ---------------------------------------
;
;   D[6:0]: data bits to indicate position of servo (128 positions available)
;   EN: Enable bit
;       1: Enable servo output
;       0: Disable servo output

i2c_state   equ 0x70
i2c_buffer  equ 0x71
current_reg equ 0x72

; Reset vector
    org 0x0000
    goto init_pic

; Interrupt vector
    org 0x0004

    ; Increase frequency to 8MHz
    banksel OSCCON
    movlw 0x70
    movwf OSCCON

    banksel PIR1
    btfsc PIR1, SSP1IF
    call handle_i2c_interrupt

    ; Switch back frequency to 500kHz
    banksel OSCCON
    movlw 0x38
    movwf OSCCON

    retfie

; Initialize PIC
; --------------
init_pic

    ; Clear interrupt register: disable all interrupts
    clrf INTCON

    ; Configure oscillator to 500kHz
    banksel OSCCON
    movlw 0x38
    movwf OSCCON

    ; Clear variables
    movlw 0x20
    movwf FSR0H
    clrf FSR0L
    clrf W
    movwi 0[FSR0]       ; servo_con_0 = 0
    movwi 1[FSR0]       ; servo_con_1 = 0
    movwi 2[FSR0]       ; servo_con_2 = 0
    movwi 3[FSR0]       ; servo_con_3 = 0

    clrf i2c_state
    clrf i2c_buffer
    clrf current_reg

    ; Configure gpios
    banksel ANSELA
    clrf ANSELA
    banksel LATA
    clrf LATA
    banksel TRISA
    movlw 0x0A
    movwf TRISA

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

    banksel SSPCON1         ; CKP is not set to 0 when NAK is received
    btfsc SSPCON1, CKP
    return

    btfss SSPSTAT, R_NOT_W
    call handle_i2c_write
    btfsc SSPSTAT, R_NOT_W
    call handle_i2c_read

    banksel SSPCON2
    btfsc SSPCON2, SEN      ; Release clock if clock stretching is enabled
    bsf SSPCON1, CKP

    return

handle_i2c_write
    banksel SSPBUF
    movf SSPBUF, W          ; Read buffer
    movwf i2c_buffer

    banksel SSPSTAT
    btfsc SSPSTAT, D_NOT_A
    goto handle_i2c_write_1
                                ;   if address
    movlw 0x1                   ;       current_state = 1
    movwf i2c_state
    return

handle_i2c_write_1              ;   else if current_state == 1
                                ;       current_reg = i2c_buffer & 0x3
                                ;       current_state = 2
    movf i2c_state, W
    sublw 0x01
    btfss STATUS, Z
    goto handle_i2c_write_2

    movf i2c_buffer, W
    andlw 0x3
    movwf current_reg
    lslf i2c_state, 1
    return

handle_i2c_write_2              ;   else if current_state == 2
                                ;       regs[current_reg] = i2c_buffer
                                ;       current_state = 4
    movf i2c_state, W
    sublw 0x02
    btfss STATUS, Z
    return

    movlw 0x20
    movwf FSR0H
    movf current_reg, W
    movwf FSR0L
    movf i2c_buffer, W
    movwi 0[FSR0]

    lslf i2c_state, 1
    return

handle_i2c_read         ;   SSPBUF = regs[current_reg]
    movlw 0x20
    movwf FSR0H
    movf current_reg, W
    movwf FSR0L
    moviw 0[FSR0]
    banksel SSPBUF
    movwf SSPBUF

    return

    end
