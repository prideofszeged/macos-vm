#!/usr/bin/env bash
set -e

# macOS VM Bootstrap Script
# Clones upstream OSX-KVM, applies AMD Ryzen patches, and optionally runs setup.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_REPO="https://github.com/kholia/OSX-KVM.git"
TARGET_DIR="${1:-$SCRIPT_DIR/OSX-KVM}"
RUN_SETUP=true

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --no-setup) RUN_SETUP=false ;;
        --help|-h)
            echo "Usage: bootstrap.sh [TARGET_DIR] [--no-setup]"
            echo ""
            echo "  TARGET_DIR   Where to clone OSX-KVM (default: ./OSX-KVM)"
            echo "  --no-setup   Skip running setup.sh after patching"
            exit 0
            ;;
    esac
done

# Handle positional arg (skip flags)
if [[ "${1:-}" != --* ]] && [[ -n "${1:-}" ]]; then
    TARGET_DIR="$1"
fi

echo "================================"
echo "  macOS VM Bootstrap"
echo "================================"
echo ""
echo "Target directory: $TARGET_DIR"
echo ""

# Step 1: Clone upstream
if [[ -d "$TARGET_DIR/.git" ]]; then
    echo "[1/4] OSX-KVM already cloned, pulling latest..."
    git -C "$TARGET_DIR" pull --ff-only || echo "  (pull failed, continuing with existing)"
else
    echo "[1/4] Cloning upstream OSX-KVM..."
    git clone "$UPSTREAM_REPO" "$TARGET_DIR"
fi
echo ""

# Step 2: Apply patches
echo "[2/4] Applying AMD Ryzen patches..."
cd "$TARGET_DIR"
if git apply --check "$SCRIPT_DIR/patches/OpenCore-Boot.sh.patch" 2>/dev/null; then
    git apply "$SCRIPT_DIR/patches/OpenCore-Boot.sh.patch"
    echo "  Applied OpenCore-Boot.sh patch"
else
    echo "  Patch already applied or conflicts detected, skipping"
    echo "  (If this is wrong, check patches/OpenCore-Boot.sh.patch manually)"
fi
echo ""

# Step 3: Copy custom files
echo "[3/4] Copying custom scripts..."
cp "$SCRIPT_DIR/files/setup.sh" "$TARGET_DIR/setup.sh"
cp "$SCRIPT_DIR/files/macos-launcher.sh" "$TARGET_DIR/macos-launcher.sh"
cp "$SCRIPT_DIR/files/kvm-macos.conf" "$TARGET_DIR/kvm-macos.conf"
chmod +x "$TARGET_DIR/setup.sh" "$TARGET_DIR/macos-launcher.sh"
echo "  Copied: setup.sh, macos-launcher.sh, kvm-macos.conf"
echo ""

# Step 4: Run setup (optional)
if $RUN_SETUP; then
    echo "[4/4] Running setup..."
    echo ""
    cd "$TARGET_DIR"
    bash setup.sh
else
    echo "[4/4] Skipping setup (--no-setup flag)"
    echo ""
    echo "To run setup later:"
    echo "  cd $TARGET_DIR && bash setup.sh"
fi

echo ""
echo "================================"
echo "  Bootstrap Complete!"
echo "================================"
echo ""
echo "Your macOS VM is ready at: $TARGET_DIR"
echo ""
echo "Next steps:"
echo "  cd $TARGET_DIR"
echo "  ./macos-launcher.sh        # Start the VM"
echo ""
echo "SSH into the VM (after macOS is installed + SSH enabled):"
echo "  ssh -p 2222 user@localhost"
echo ""
