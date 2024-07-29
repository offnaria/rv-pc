LINUX_VERSION     := v5.0
RISCVPK_VERSION   := v1.0.0
BUILDROOT_VERSION := 2019.11.3

LINUX_DIR     := linux-$(LINUX_VERSION)
RISCVPK_DIR   := riscv-pk-$(RISCVPK_VERSION)
BUILDROOT_DIR := buildroot-$(BUILDROOT_VERSION)

TRIPLE := riscv32-unknown-linux-gnu

PATCH_DIR      := rvpc_patch
DEVICETREE_DIR := devicetree
INITMEMGEN_DIR := initmem_gen

NPARALLEL ?= $(shell nproc)

# Memory initialization data

.PHONY: initmem
initmem: $(INITMEMGEN_DIR)/initmem.bin

$(INITMEMGEN_DIR)/initmem.bin: $(INITMEMGEN_DIR)/initmem_gen $(RISCVPK_DIR)/build/bbl.bin $(BUILDROOT_DIR)/output/images/rootfs.ext4 $(DEVICETREE_DIR)/devicetree.dtb
	$^

$(INITMEMGEN_DIR)/initmem_gen: $(INITMEMGEN_DIR)/main.c $(INITMEMGEN_DIR)/Makefile
	make -C $(INITMEMGEN_DIR)

# Device tree

.PHONY: dtb
dtb: $(DEVICETREE_DIR)/devicetree.dtb

$(DEVICETREE_DIR)/devicetree.dtb:
	dtc -I dts -O dtb $(dir $@)/devicetree_75mhz.dts -o $@

# buildroot

.PHONY: buildroot
buildroot: $(BUILDROOT_DIR)/output/images/rootfs.ext4

$(BUILDROOT_DIR)/output/images/rootfs.ext4:
#	patch -d $(BUILD_DIR) -p1 -N < $(PATCH_DIR)/buildroot.patch || true
	cp $(PATCH_DIR)/rv32ima_buildroot_config $(BUILDROOT_DIR)/.config
	cp -r $(PATCH_DIR)/overlay $(BUILDROOT_DIR)/
#	unset LD_LIBRARY_PATH
	make -C $(BUILDROOT_DIR) -j$(NPARALLEL)

# BBL

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
