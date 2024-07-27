LINUX_VERSION   := v5.0
RISCVPK_VERSION := v1.0.0

LINUX_DIR    := linux-$(LINUX_VERSION)
RISCVPK_DIR  := riscv-pk-$(RISCVPK_VERSION)

TRIPLE := riscv32-unknown-linux-gnu

PATCH_DIR := rvpc_patch

NPARALLEL ?= $(shell nproc)

.PHONY: bbl
bbl: $(RISCVPK_DIR)/build/bbl.bin

$(RISCVPK_DIR)/build/bbl.bin: $(RISCVPK_DIR)/build/bbl
	$(TRIPLE)-objcopy -O binary $< $@

$(RISCVPK_DIR)/build/bbl: $(LINUX_DIR)/vmlinux
	patch -d $(RISCVPK_DIR) -p1 -N < $(PATCH_DIR)/riscv-pk.patch || true
	mkdir -p $(dir $@)
	cd $(dir $@) && \
	../configure --prefix=$(dir $(shell which $(TRIPLE)-gcc)) --enable-logo \
				 --enable-print-device-tree --host=$(TRIPLE) \
				 --with-arch=rv32ima_zicsr_zifencei --with-payload=../../$(LINUX_DIR)/vmlinux
	make -C $(dir $@) -j$(NPARALLEL)

# Linux kernel

.PHONY: vmlinux
.PRECIOUS: $(LINUX_DIR)/vmlinux
vmlinux: $(LINUX_DIR)/vmlinux

$(LINUX_DIR)/vmlinux:
	patch -d $(LINUX_DIR) -p1 -N < $(PATCH_DIR)/linux.patch || true
	make -C $(LINUX_DIR) mrproper
	make -C $(LINUX_DIR) ARCH=riscv CROSS_COMPILE=$(TRIPLE)- defconfig
	cp $(PATCH_DIR)/rv32ima_kernel_config $(LINUX_DIR)/.config
	make -C $(LINUX_DIR) -j$(NPARALLEL) V=1 ARCH=riscv CROSS_COMPILE=$(TRIPLE)- vmlinux

.PHONY: clean

clean:
	rm -rf $(RISCVPK_DIR)/build
	make -C $(LINUX_DIR) clean
