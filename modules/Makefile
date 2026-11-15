# This Makefile is used by DKMS and kernel kbuild.  Always expose `all` even
# when DKMS supplies KERNELRELEASE in the environment.
obj-m += elan2513-enum.o
obj-m += i2c-hid.o
obj-m += i2c-hid-acpi.o

i2c-hid-y := i2c-hid-core.o i2c-hid-dmi-quirks.o

KVER ?= $(shell uname -r)
.PHONY: all clean
all:
	$(MAKE) -C /lib/modules/$(KVER)/build M=$(CURDIR) modules
clean:
	$(MAKE) -C /lib/modules/$(KVER)/build M=$(CURDIR) clean
