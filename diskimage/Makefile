LINUX_VERSION   := v5.0

LINUX_DIR    := linux-$(LINUX_VERSION)

TRIPLE := riscv32-unknown-linux-gnu

PATCH_DIR := rvpc_patch

NPARALLEL ?= $(shell nproc)

.PHONY: vmlinux
vmlinux: $(LINUX_DIR)/vmlinux

$(LINUX_DIR)/vmlinux:
	patch -d $(LINUX_DIR) -p1 -N < $(PATCH_DIR)/linux.patch || true
	make -C $(LINUX_DIR) mrproper
	make -C $(LINUX_DIR) ARCH=riscv CROSS_COMPILE=$(TRIPLE)- defconfig
	cp $(PATCH_DIR)/rv32ima_kernel_config $(LINUX_DIR)/.config
	make -C $(LINUX_DIR) -j$(NPARALLEL) V=1 ARCH=riscv CROSS_COMPILE=$(TRIPLE)- vmlinux

.PHONY: clean

clean:
	rm -rf $(DOWNLOAD_DIR)
