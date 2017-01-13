## RobotArmClick

The RobotArmClick is a small board mainly consisting of a PIC12LF1552 being
controlled over I2C commands to control 4 servos.

### Build instructions (Linux)

First install the assembler:

```sh
$ sudo apt-get install gpasm
```

Then, create the firmware:

```sh
$ gpasm -p pic12lf1552 firmware.s -w1
```


### Controlling the device over I2C


The chip is configured as an i2c slave and its 7-bit address is 0x15. It has 
been tested with a bus frequency of 100kHz and 400kHz.

#### Register map
| name | address|
|:-------------:|:-------------:|
| servo enable | 0x00|
| servo 1 config| 0x01|
| servo 2 config| 0x02|
| servo 3 config| 0x03|
| servo 4 config| 0x04|

servo_enable format:
```
    ---------------------------------------
   | X | X | X | X | EN3 | EN2 | EN1 | EN0 |
    ---------------------------------------
       EN<x>:
       1: Enable output on servo <x>
       0: Disable output on servo <x>
```
servo X format:
```
    ---------------------------------------
   | X | D6 | D5 | D4 | D3 | D2 | D1 | D0 |
    ---------------------------------------

   D[6:0]: data bits to indicate position of servo (128 positions available)
```
#### Writing to a register
To write to a register, you must follow this protocol:
```
 | 0x35 | reg-addr | value |
```
 - reg-addr: Must be in range 0..4. If it is outside of the range, nothing in memory will be changed.
 - value: 8-bit value
   
Any subsequent read operations will return the value of the register at address ```reg-addr```.
#### Reading from a register

To read from a specific register, first write the register address:
```
 | 0x35 | reg-addr |
```
Then, read one byte to read the value of the register:
```
|0x36 | reg-value | 
```
