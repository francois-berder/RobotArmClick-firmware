ASM := gpasm
DEVICE := pic12lf1552

.PHONY: all
all: firmware.hex

firmware.hex: firmware.s
	$(ASM) -w1 -p $(DEVICE) $^

.PHONY: clean
clean:
	rm -rf debug/
	rm firmware.cod firmware.hex firmware.lst firmware.obj
