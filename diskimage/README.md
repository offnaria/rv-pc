# How to build a disk image of RV-PC by yourself

## Prerequisites

The build process needs [riscv-gnu-toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain). The following example shows steps to install the up-to-date version (2024.04.12) of the toolcahin on a Ubuntu machine.

```
sudo apt install -y autoconf automake autotools-dev curl python3 python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev ninja-build git cmake libglib2.0-dev libslirp-dev
git clone https://github.com/riscv-collab/riscv-gnu-toolchain.git -b 2024.04.12 --depth 1
cd riscv-gnu-toolchain
./configure --prefix=/opt/rv32ima_zicsr_zifencei --with-arch=rv32ima_zicsr_zifencei --with-abi=ilp32
sudo make -j$(nproc) linux
```

> [!NOTE]
> CSR related instructions and fence instructions has to be splitted from baseline ISA, zicsr and zifencei are corresponding sub-extension.
> (Quoted from [riscvarchive/riscv-gcc@b03be74](https://github.com/riscvarchive/riscv-gcc/commit/b03be74).)

Then, add the `bin` directory to the PATH.

```
export PATH=/opt/rv32ima_zicsr_zifencei/bin:$PATH
```

Finally, retrieve submodules of this repository.

```
git submodule update --init --recursive
```

## Build Linux kernel

You can simply build the linux kernel by tiping the following command in this directory.

```
make vmlinux
```

> [!NOTE]
> The `vmlinux` rule attaches a patch file, which is created to make the build process possible with a newer version of riscv-gnu-toolchain (e.g. 2024.04.12).

## Build BBL

You can simply build BBL (Berkeley Boot Loader) by tiping the following command in this directory.

```
make bbl
```

## Build buildroot

**This part is updated later. The following instruction is tentative.**

```
make buildroot
```

## Build device tree

You can simply build device tree by typing the following command in this directory.

```
make dtb
```

## Generate memory initialization data

You can simply generate the memory initialization data (`initmem.bin`) by typing the following command in this directory.

```
make initmem
```

