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
$ gpasm -p pic12lf1552 firmware.s
```

