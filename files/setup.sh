#!/usr/bin/env bash
set -e

# macOS VM Setup Script
# For AMD Ryzen systems running Linux

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_VERSION="${1:-7}"  # Default to Sonoma (7)

echo "================================"
echo "  macOS VM Setup Script"
echo "================================"
echo ""

# Check if running as root (we don't want that)
if [[ $EUID -eq 0 ]]; then
    echo "Don't run this as root. Run as your normal user."
    echo "You'll be prompted for sudo when needed."
    exit 1
fi

# Check CPU virtualization
echo "[1/7] Checking CPU virtualization..."
if grep -q -E "(vmx|svm)" /proc/cpuinfo; then
    if grep -q "svm" /proc/cpuinfo; then
        CPU_TYPE="AMD"
        KVM_MODULE="kvm_amd"
    else
        CPU_TYPE="Intel"
        KVM_MODULE="kvm_intel"
    fi
    echo "  ✓ $CPU_TYPE virtualization supported"
else
    echo "  ✗ No virtualization support found. Enable VT-x/SVM in BIOS."
    exit 1
fi

# Check KVM
echo "[2/7] Checking KVM access..."
if [[ -e /dev/kvm ]]; then
    if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
        echo "  ✓ KVM accessible"
    else
        echo "  ✗ KVM exists but no permission. Add yourself to kvm group:"
        echo "    sudo usermod -aG kvm $USER"
        exit 1
    fi
else
    echo "  ✗ /dev/kvm not found. Install KVM:"
    echo "    sudo apt install qemu-kvm"
    exit 1
fi

# Install dependencies
echo "[3/7] Installing dependencies..."
if command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y qemu-system-x86 qemu-utils dmg2img
    echo "  ✓ Dependencies installed"
elif command -v dnf &> /dev/null; then
    sudo dnf install -y qemu-kvm qemu-img dmg2img
    echo "  ✓ Dependencies installed"
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm qemu-full dmg2img
    echo "  ✓ Dependencies installed"
else
    echo "  ! Unknown package manager. Install manually: qemu, dmg2img"
fi

# Set up kernel module config
echo "[4/7] Configuring kernel modules..."
if [[ "$CPU_TYPE" == "AMD" ]]; then
    sudo tee /etc/modprobe.d/kvm-macos.conf > /dev/null << 'KCONF'
options kvm_amd nested=1
options kvm ignore_msrs=1
options kvm report_ignored_msrs=0
KCONF
else
    sudo tee /etc/modprobe.d/kvm-macos.conf > /dev/null << 'KCONF'
options kvm_intel nested=1
options kvm ignore_msrs=1
options kvm report_ignored_msrs=0
KCONF
fi
echo "  ✓ Kernel module config written"

# Apply kernel params now
echo "  Applying kernel parameters..."
sudo sh -c 'echo 1 > /sys/module/kvm/parameters/ignore_msrs' 2>/dev/null || true
echo "  ✓ Parameters applied"

# Download macOS if needed
echo "[5/7] Checking macOS installer..."
cd "$SCRIPT_DIR"
if [[ ! -f "BaseSystem.img" ]]; then
    echo "  Downloading macOS (option $MACOS_VERSION)..."
    echo "  (1=HighSierra, 2=Mojave, 3=Catalina, 4=BigSur, 5=Monterey, 6=Ventura, 7=Sonoma)"
    echo "$MACOS_VERSION" | ./fetch-macOS-v2.py

    echo "  Converting DMG to IMG..."
    if command -v dmg2img &> /dev/null; then
        dmg2img BaseSystem.dmg BaseSystem.img
    else
        qemu-img convert BaseSystem.dmg -O raw BaseSystem.img
    fi
    echo "  ✓ macOS installer ready"
else
    echo "  ✓ BaseSystem.img already exists"
fi

# Create virtual disk if needed
echo "[6/7] Checking virtual disk..."
if [[ ! -f "mac_hdd_ng.img" ]]; then
    echo "  Creating 80GB virtual disk..."
    qemu-img create -f qcow2 mac_hdd_ng.img 80G
    echo "  ✓ Virtual disk created"
else
    echo "  ✓ Virtual disk already exists"
fi

# Install desktop launcher
echo "[7/7] Installing desktop launcher..."
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/macos-vm.desktop << DESKTOP
[Desktop Entry]
Name=macOS VM
Comment=Launch macOS Sonoma VM
Exec=$SCRIPT_DIR/macos-launcher.sh
Icon=computer
Terminal=true
Type=Application
Categories=System;Emulator;
DESKTOP
update-desktop-database ~/.local/share/applications/ 2>/dev/null || true
echo "  ✓ Desktop launcher installed"

echo ""
echo "================================"
echo "  Setup Complete!"
echo "================================"
echo ""
echo "To start the VM:"
echo "  $SCRIPT_DIR/macos-launcher.sh"
echo ""
echo "Or search 'macOS VM' in your app menu."
echo ""
echo "First boot: Select 'macOS Base System' to install."
echo "  1. Open Disk Utility, format the 80GB disk as APFS"
echo "  2. Run the macOS installer"
echo "  3. After reboots, select 'Macintosh HD' to boot installed system"
echo ""
