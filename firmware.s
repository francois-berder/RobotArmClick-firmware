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

#define SERVO_1_GPIO_MASK       (0x20)
#define SERVO_2_GPIO_MASK       (0x10)
#define SERVO_3_GPIO_MASK       (0x01)
#define SERVO_4_GPIO_MASK       (0x04)

;   MEMORY MAP
;
;       name        |       address
;-----------------------------------
;    servo_con_1    |       0x21 (bank 0)
;    servo_con_2    |       0x22 (bank 0)
;    servo_con_3    |       0x23 (bank 0)
;    servo_con_4    |       0x24 (bank 0)
;    i2c_state      |       0x70 (shared)
;    i2c_buffer     |       0x71 (shared)
;    current_reg    |       0x72 (shared)
;    servo_enable   |       0x73 (shared)
;    servo_mask     |       0x74 (shared)

;   Each servo_con_X variable has this format:
;    ---------------------------------------
;   | X | D6 | D5 | D4 | D3 | D2 | D1 | D0 |
;    ---------------------------------------
;
;   D[6:0]: data bits to indicate position of servo (128 positions available)
;
; servo_enable:
;
;    ---------------------------------------
;   | B4 | B3 | B2 | B1 | EN4 | EN3 | EN2 | EN1 |
;    ---------------------------------------
;
;   EN<x>:
;       1: Enable output on servo <x>
;       0: Disable output on servo <x>
;
;   B<x>:
;       1: Currently servicing this servo
;       0: Not currently servicing this servo

i2c_state       equ 0x70
i2c_buffer      equ 0x71
current_reg     equ 0x72
servo_enable    equ 0x73
servo_mask      equ 0x74

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
    clrf WREG
    movwi 1[FSR0]       ; servo_con_1 = 0
    movwi 2[FSR0]       ; servo_con_2 = 0
    movwi 3[FSR0]       ; servo_con_3 = 0
    movwi 4[FSR0]       ; servo_con_4 = 0

    clrf i2c_state
    clrf i2c_buffer
    clrf current_reg
    clrf servo_enable
    clrf servo_mask

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
    ; If no servo is enabled, set device to sleep
    movf servo_enable, 1
    btfsc STATUS, Z
    sleep
    movf servo_enable, 1    ; servo_enable might have been written by the
    btfsc STATUS, Z         ; i2c master, so we need to load it again.
    goto loop

    call process_servo

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
                                ;       current_reg = i2c_buffer
                                ;       current_state = 2
    movf i2c_state, W
    sublw 0x01
    btfss STATUS, Z
    goto handle_i2c_write_2

    movf i2c_buffer, W
    movwf current_reg

    lslf i2c_state, 1
    return

handle_i2c_write_2              ;   else if current_state == 2
                                ;       if current_reg == 0
                                ;           servo_enable = (servo_enable & 0xF0) | (i2c_buffer & 0x0F)
                                ;           current_reg++
                                ;       else if current_reg <= 4
                                ;           regs[current_reg++] = i2c_buffer
    movf i2c_state, W
    sublw 0x02
    btfss STATUS, Z
    return

    movf current_reg, W
    btfss STATUS, Z
    goto handle_i2c_write_2a

    movf servo_enable, W
    andlw 0xF0
    andwf servo_enable

    movf i2c_buffer, W
    andlw 0x0F
    iorwf servo_enable
    incf current_reg
    goto handle_i2c_write_2b

handle_i2c_write_2a
    addlw 0xFB                  ; 0xFB = 251
    btfsc STATUS, C
    goto handle_i2c_write_2b

    movlw 0x20
    movwf FSR0H
    movf current_reg, W
    movwf FSR0L
    movf i2c_buffer, W
    movwi 0[FSR0]
    incf current_reg

handle_i2c_write_2b
    return

handle_i2c_read         ;   if current_reg == 0
                        ;       SSPBUF = (servo_enable & 0x0F)
                        ;       current_reg++
                        ;   else if current_reg <= 4
                        ;       SSPBUF = regs[current_reg++]
                        ;   else
                        ;       SSPBUF = 0

    movf current_reg, W
    btfss STATUS, Z
    goto handle_i2c_read_1

    movf servo_enable, W
    andlw 0x0F
    incf current_reg
    goto handle_i2c_read_end

handle_i2c_read_1
    addlw 0xFB                  ; 0xFB = 251
    btfss STATUS, C
    goto handle_i2c_read_2

    clrf WREG
    goto handle_i2c_read_end

handle_i2c_read_2
    movlw 0x20
    movwf FSR0H
    movf current_reg, W
    movwf FSR0L
    moviw 0[FSR0]
    incf current_reg

handle_i2c_read_end
    banksel SSPBUF
    movwf SSPBUF

    return


process_servo
    btfss servo_enable, 0
    goto process_servo_2

    movlw SERVO_1_GPIO_MASK
    movwf servo_mask
    bsf servo_enable, 4
    call perform_pulse
    bcf servo_enable, 4

process_servo_2
    btfss servo_enable, 1
    goto process_servo_3

    movlw SERVO_2_GPIO_MASK
    movwf servo_mask
    bsf servo_enable, 5
    call perform_pulse
    bcf servo_enable, 5

process_servo_3
    btfss servo_enable, 2
    goto process_servo_4

    movlw SERVO_3_GPIO_MASK
    movwf servo_mask
    bsf servo_enable, 6
    call perform_pulse
    bcf servo_enable, 6

process_servo_4
    btfss servo_enable, 3
    goto process_servo_end

    movlw SERVO_4_GPIO_MASK
    movwf servo_mask
    bsf servo_enable, 7
    call perform_pulse
    bcf servo_enable, 7

process_servo_end

    return


perform_pulse

    ; Disable interrupt to prevent servicing i2c bus.
    ; This ensures that the length of the pulse is not longer than it should.
    banksel INTCON
    bcf INTCON, GIE

    movf servo_mask, W          ; Set GPIO high
    banksel LATA
    movwf LATA

    ; Padding to ensure that GPIO is high at least 500us

    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop


    movlw 0x20                  ; Load content of servo_con_<x>
    movwf FSR0H
    btfsc servo_enable, 4
    movlw 0x01
    btfsc servo_enable, 5
    movlw 0x02
    btfsc servo_enable, 6
    movlw 0x03
    btfsc servo_enable, 7
    movlw 0x04
    movwf FSR0L
    moviw 0[FSR0]

    sublw 0xFF
    brw

    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    clrf LATA
    banksel INTCON
    bsf INTCON, GIE

    moviw 0[FSR0]
    brw

    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    call wait_one_ms
    call wait_one_ms

    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    return


; 121 nop instructions
; call + return = 4 nop instructions
; Total: 125 instructions, 500 clock cycles
wait_one_ms
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    return

    end
