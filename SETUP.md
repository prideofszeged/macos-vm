# macOS VM Setup Documentation

## Overview

This repo provides a lightweight overlay for [kholia/OSX-KVM](https://github.com/kholia/OSX-KVM), storing only the customizations needed to run macOS Sonoma on an AMD Ryzen 7 5700X system. Instead of maintaining a full fork, a bootstrap script clones the upstream repo and applies patches + custom files on top.

## Hardware & Software Context

- **CPU**: AMD Ryzen 7 5700X (8 cores / 16 threads, Zen 3)
- **Host OS**: Linux (Ubuntu/NixOS, kernel 6.x)
- **Guest OS**: macOS Sonoma (14.x)
- **Hypervisor**: QEMU/KVM with OpenCore bootloader
- **VM allocation**: 6 cores, 12 threads, 16GB RAM (leaves 2 cores + 4GB for the host)

## Repository Structure

```
macos-vm/
├── bootstrap.sh                    # Clones upstream + patches + setup
├── patches/
│   └── OpenCore-Boot.sh.patch      # AMD Ryzen QEMU config diff
├── files/
│   ├── setup.sh                    # Automated VM setup (deps, download, disk)
│   ├── macos-launcher.sh           # Background VM launcher (start/stop/restart)
│   └── kvm-macos.conf              # Kernel module config for KVM
├── SETUP.md                        # This file
├── README.md                       # Brief human-readable readme
└── .gitignore
```

## File Purposes

### `bootstrap.sh`
Entry point. Clones `kholia/OSX-KVM` into a subdirectory, applies the OpenCore patch, copies custom scripts in, and optionally runs `setup.sh`. Supports:
- `--no-setup` flag to skip automated setup
- Custom target directory as first argument
- Re-running safely (pulls if already cloned, skips patch if already applied)

### `patches/OpenCore-Boot.sh.patch`
A unified diff that modifies the upstream `OpenCore-Boot.sh` QEMU launch script. See "The Patch" section below for details.

### `files/setup.sh`
Automated setup that:
1. Checks CPU virtualization support (AMD SVM / Intel VT-x)
2. Verifies KVM access (`/dev/kvm`)
3. Installs dependencies (`qemu-system-x86`, `dmg2img`)
4. Writes kernel module config to `/etc/modprobe.d/kvm-macos.conf`
5. Downloads macOS Sonoma installer via `fetch-macOS-v2.py`
6. Converts DMG to IMG
7. Creates an 80GB qcow2 virtual disk
8. Installs a `.desktop` launcher for the app menu

### `files/macos-launcher.sh`
VM lifecycle manager. Runs QEMU in background via `nohup` so closing the terminal doesn't kill the VM. Supports:
- `start` / `stop` / `restart` / `status` / `log` commands
- Interactive menu when run without arguments
- PID tracking in `.macos-vm.pid`

### `files/kvm-macos.conf`
Kernel module parameters installed to `/etc/modprobe.d/`:
```
options kvm_amd nested=1
options kvm ignore_msrs=1
options kvm report_ignored_msrs=0
```
- `nested=1`: Enables nested virtualization
- `ignore_msrs=1`: Required for macOS — prevents KVM crashes on unhandled MSR accesses
- `report_ignored_msrs=0`: Suppresses kernel log spam from ignored MSRs

## The Patch: What It Changes and Why

The patch modifies 5 settings in `OpenCore-Boot.sh`:

### 1. CPU Model: `Skylake-Client` → `Haswell-noTSX`
- **Why**: Upstream defaults to `Skylake-Client` (for Sequoia/Tahoe). For Sonoma on AMD, `Haswell-noTSX` is more stable
- **Why not just Haswell**: The `noTSX` variant avoids TSX (Transactional Synchronization Extensions) bugs that cause instability in KVM
- The patch also swaps which CPU line is active vs commented out

### 2. RAM: `4096` → `16384` (4GB → 16GB)
- **Why**: macOS Sonoma needs at least 8GB to run well; 16GB provides comfortable headroom for development work

### 3. CPU Topology: `2 cores / 4 threads` → `6 cores / 12 threads`
- **Why**: Matches half the Ryzen 7 5700X (8c/16t), leaving resources for the host

### 4. CPU Flags: Added `+avx2,+fma,+bmi1,+bmi2,+smep`
- **Why**: These instruction set extensions are available on Zen 3 and expected by Sonoma:
  - `avx2`: 256-bit vector operations (required by Sonoma)
  - `fma`: Fused multiply-add (performance)
  - `bmi1/bmi2`: Bit manipulation (used by compilers, crypto)
  - `smep`: Supervisor Mode Execution Prevention (security)

## How bootstrap.sh Works Step-by-Step

1. Parses arguments (`TARGET_DIR`, `--no-setup`)
2. Clones `https://github.com/kholia/OSX-KVM.git` into target directory (or pulls if already cloned)
3. Runs `git apply --check` to test the patch, then applies it (skips if already applied)
4. Copies `setup.sh`, `macos-launcher.sh`, and `kvm-macos.conf` into the clone
5. Makes scripts executable
6. If `--no-setup` was not passed, runs `setup.sh` which handles dependencies, macOS download, and disk creation
7. Prints next-steps instructions

## How to Modify Settings

### RAM
Edit `files/setup.sh` is not needed — RAM is controlled by the patch. To change:
1. Edit `patches/OpenCore-Boot.sh.patch`, change `16384` to your desired MiB value
2. Or after bootstrap, edit `OSX-KVM/OpenCore-Boot.sh` directly: `ALLOCATED_RAM="32768"`

### CPU Cores/Threads
Same approach — edit the patch or `OSX-KVM/OpenCore-Boot.sh`:
```bash
CPU_CORES="8"
CPU_THREADS="16"
```

### macOS Version
`setup.sh` defaults to Sonoma (option 7). To change:
```bash
cd OSX-KVM && bash setup.sh 6   # Ventura
cd OSX-KVM && bash setup.sh 5   # Monterey
```
Note: Versions older than Sonoma may work with the `Penryn` CPU model (revert the patch).

### Disk Size
Edit `files/setup.sh`, change `80G` in the `qemu-img create` line:
```bash
qemu-img create -f qcow2 mac_hdd_ng.img 256G
```
This only affects new disks. Existing disks can be resized with:
```bash
qemu-img resize mac_hdd_ng.img +100G
```

### Display Resolution
The OVMF vars file controls the resolution. The default uses `OVMF_VARS-1920x1080.fd`. To change, replace it with another resolution variant from the repo (e.g., `OVMF_VARS-1024x768.fd`).

## Updating When Upstream Changes

```bash
cd OSX-KVM
git stash           # Stash local changes (the applied patch)
git pull            # Pull upstream updates
git stash pop       # Re-apply local changes

# If there are conflicts in OpenCore-Boot.sh:
# 1. Resolve manually
# 2. Update the patch: git diff > ../patches/OpenCore-Boot.sh.patch
```

Or re-run bootstrap from scratch:
```bash
rm -rf OSX-KVM
./bootstrap.sh
```

## File Sharing Between Host and VM

### SSH (Port 2222)
The QEMU config forwards host port 2222 to guest port 22:
```bash
# From host, after enabling SSH in macOS System Settings > General > Sharing
ssh -p 2222 your-mac-user@localhost

# Copy files
scp -P 2222 file.txt your-mac-user@localhost:~/Desktop/
```

### QEMU SMB Sharing
Add this to the `-netdev` line in `OpenCore-Boot.sh`:
```
-netdev user,id=net0,hostfwd=tcp::2222-:22,smb=/path/to/shared/folder
```
Then in macOS: Finder > Go > Connect to Server > `smb://10.0.2.4/qemu`

## Troubleshooting

### VM won't boot / kernel panic
- Ensure `ignore_msrs=1` is active: `cat /sys/module/kvm/parameters/ignore_msrs`
- If it shows 0, run: `sudo sh -c 'echo 1 > /sys/module/kvm/parameters/ignore_msrs'`

### "KVM not available" error
- Check `/dev/kvm` exists and is accessible
- Ensure virtualization is enabled in BIOS (SVM for AMD)
- Add yourself to the kvm group: `sudo usermod -aG kvm $USER` (log out/in after)

### Slow performance
- Verify KVM is active (not TCG emulation): check QEMU log for "kvm" mentions
- Ensure you're not overallocating cores (leave at least 2 for the host)
- Use `virtio` drivers in macOS for better I/O performance

### Black screen after boot
- Try a different OVMF resolution file
- Wait 30-60 seconds — first boot can be slow
- Check the QEMU log: `tail -50 OSX-KVM/vm.log`

### Patch fails to apply
- Upstream may have changed `OpenCore-Boot.sh`
- Apply changes manually (see "The Patch" section for what to change)
- Regenerate the patch after manual edits
