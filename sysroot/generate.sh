#!/bin/bash
set -e

WORK_DIR="$(pwd)/sysroots-build"
OUTPUT_DIR="$(pwd)"

# Check dependencies
NEED_INSTALL=()
if ! command -v debootstrap &> /dev/null; then
    echo "  - debootstrap not found"
    NEED_INSTALL+=("debootstrap")
fi
if ! command -v qemu-aarch64-static &> /dev/null; then
    echo "  - qemu-user-static not found"
    NEED_INSTALL+=("qemu-user-static")
fi

if [ ${#NEED_INSTALL[@]} -gt 0 ]; then
    echo "Installing missing dependencies: ${NEED_INSTALL[*]}"
    sudo apt update
    sudo apt install -y "${NEED_INSTALL[@]}"
else
    echo "All dependencies installed ✓"
fi

if [ ! -f /usr/bin/qemu-aarch64-static ]; then
    echo "ERROR: qemu-aarch64-static not found at /usr/bin/qemu-aarch64-static"
    echo "Please install it manually: sudo apt install qemu-user-static"
    exit 1
fi

echo "=== Creating Ubuntu 16.04 (Xenial) sysroots ==="
mkdir -p "$WORK_DIR"

create_sysroot() {
    local ARCH=$1
    local SYSROOT_NAME="ubuntu16-${ARCH}-sysroot"
    local SYSROOT_PATH="$WORK_DIR/$SYSROOT_NAME"
    
    echo ""
    echo "=== Creating $ARCH sysroot ==="
    
    if [ -d "$SYSROOT_PATH" ]; then
        echo "Removing existing $SYSROOT_PATH..."
        sudo rm -rf "$SYSROOT_PATH"
    fi
    
    local MIRROR
    if [ "$ARCH" = "amd64" ]; then
        MIRROR="http://archive.ubuntu.com/ubuntu"
    else
        MIRROR="http://ports.ubuntu.com/ubuntu-ports"
    fi
    
    # For ARM64 use two-stage debootstrap
    if [ "$ARCH" = "arm64" ]; then
        echo "Running debootstrap first stage for $ARCH..."
        sudo debootstrap --arch=$ARCH --variant=minbase --foreign xenial "$SYSROOT_PATH" "$MIRROR"
        
        echo "Copying qemu-aarch64-static..."
        sudo cp /usr/bin/qemu-aarch64-static "$SYSROOT_PATH/usr/bin/"
        
        echo "Running debootstrap second stage..."
        sudo chroot "$SYSROOT_PATH" /debootstrap/debootstrap --second-stage
    else
        echo "Running debootstrap for $ARCH..."
        sudo debootstrap --arch=$ARCH --variant=minbase xenial "$SYSROOT_PATH" "$MIRROR"
    fi
    
    echo "Configuring sources.list..."
    sudo tee "$SYSROOT_PATH/etc/apt/sources.list" > /dev/null << EOF
deb $MIRROR xenial main universe
deb $MIRROR xenial-updates main universe
deb $MIRROR xenial-security main universe
EOF
    
    # Mount necessary filesystems for chroot
    echo "Mounting filesystems..."
    sudo mount -t proc /proc "$SYSROOT_PATH/proc" || true
    sudo mount -t sysfs /sys "$SYSROOT_PATH/sys" || true
    sudo mount --bind /dev "$SYSROOT_PATH/dev" || true
    sudo mount --bind /dev/pts "$SYSROOT_PATH/dev/pts" || true
    
    echo "Installing development packages..."
    sudo chroot "$SYSROOT_PATH" /bin/bash << 'CHROOT_EOF'
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y \
    build-essential \
    libxkbcommon-dev libxkbcommon-x11-dev \
    libgtk-3-dev libgdk-pixbuf2.0-dev \
    libpango1.0-dev libcairo2-dev \
    libatk1.0-dev libpulse-dev \
    libglib2.0-dev libgl1-mesa-dev libglu1-mesa-dev \
    libcups2-dev libnotify-dev \
    libx11-dev libxext-dev libxrender-dev \
    libicu-dev libicu55
apt clean
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/*
CHROOT_EOF
    
    # Unmount filesystems
    echo "Unmounting filesystems..."
    sudo umount "$SYSROOT_PATH/proc" || true
    sudo umount "$SYSROOT_PATH/sys" || true
    sudo umount "$SYSROOT_PATH/dev/pts" || true
    sudo umount "$SYSROOT_PATH/dev" || true
    
    # Remove qemu from sysroot
    if [ "$ARCH" = "arm64" ]; then
        sudo rm -f "$SYSROOT_PATH/usr/bin/qemu-aarch64-static"
    fi

    # Remove /dev from sysroot (device nodes break tar extraction)
    sudo rm -rf "$SYSROOT_PATH/dev"
    sudo mkdir -p "$SYSROOT_PATH/dev"
    
    echo "Optimizing size..."
    sudo rm -rf "$SYSROOT_PATH/usr/share/doc/"*
    sudo rm -rf "$SYSROOT_PATH/usr/share/man/"*
    sudo rm -rf "$SYSROOT_PATH/usr/share/info/"*
    sudo find "$SYSROOT_PATH/usr/share/locale" -mindepth 1 -maxdepth 1 ! -name 'en*' -exec rm -rf {} \; 2>/dev/null || true
    sudo find "$SYSROOT_PATH" -name "*.la" -delete
    
    echo "Creating archive..."
    cd "$WORK_DIR"
    sudo tar -czf "$OUTPUT_DIR/${SYSROOT_NAME}.tar.gz" "$SYSROOT_NAME/"
    cd - > /dev/null
    
    local SIZE=$(du -h "$OUTPUT_DIR/${SYSROOT_NAME}.tar.gz" | cut -f1)
    echo "Archive created: ${SYSROOT_NAME}.tar.gz (${SIZE})"
    
    echo "Cleaning up..."
    sudo rm -rf "$SYSROOT_PATH"
}

create_sysroot "amd64"
create_sysroot "arm64"

echo ""
echo "=== Done! ==="
echo "Archives created in: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"/*.tar.gz
echo ""
echo "Cleaning up build directory..."
sudo rm -rf "$WORK_DIR"
echo "Complete!"
