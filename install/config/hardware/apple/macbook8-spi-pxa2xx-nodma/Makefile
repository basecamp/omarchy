obj-m := spi_pxa2xx_pci_nodma.o
spi_pxa2xx_pci_nodma-objs := spi-pxa2xx-pci-nodma.o
EXTRA_CFLAGS += -I$(src)

all:
	$(MAKE) -C /lib/modules/$(KERNELRELEASE)/build M=$(PWD) modules

clean:
	$(MAKE) -C /lib/modules/$(KERNELRELEASE)/build M=$(PWD) clean
