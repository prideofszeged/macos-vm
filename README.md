# macos-vm

Lightweight config repo for running macOS Sonoma in a QEMU/KVM virtual machine on AMD Ryzen hardware.

This repo stores only the customizations on top of [kholia/OSX-KVM](https://github.com/kholia/OSX-KVM) — no fork needed.

## Quick Start

```bash
git clone https://github.com/stevenic/macos-vm.git
cd macos-vm
./bootstrap.sh
```

This clones upstream OSX-KVM, applies the AMD Ryzen patches, installs dependencies, downloads macOS Sonoma, and creates a virtual disk.

## What It Does

- Patches `OpenCore-Boot.sh` for AMD Ryzen 7 5700X: Haswell-noTSX CPU model, 16GB RAM, 6 cores/12 threads, AVX2/FMA/BMI instruction sets
- Provides `setup.sh` for automated dependency installation, macOS download, and disk creation
- Provides `macos-launcher.sh` for background VM management (start/stop/restart)
- Includes kernel module config for KVM with `ignore_msrs`

## Usage

```bash
# Skip automated setup (just clone + patch)
./bootstrap.sh --no-setup

# Clone to a custom location
./bootstrap.sh /path/to/my/vm

# After bootstrap, manage the VM
cd OSX-KVM
./macos-launcher.sh start
./macos-launcher.sh stop
./macos-launcher.sh status
```

## Documentation

See [SETUP.md](SETUP.md) for comprehensive documentation covering hardware context, patch details, configuration options, troubleshooting, and file sharing.
