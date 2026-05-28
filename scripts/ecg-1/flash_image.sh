#!/bin/bash
set -euo pipefail

IMAGE="${1:-android-desktop_image.bin.gz}"
TARGET_VENDOR="0781"
TARGET_PRODUCT="5588"

# Find the block device corresponding to the SanDisk (0781:5588)
find_device() {
    for dev in /sys/bus/usb/devices/*/; do
        local idVendor idProduct
        idVendor=$(cat "${dev}idVendor" 2>/dev/null || true)
        idProduct=$(cat "${dev}idProduct" 2>/dev/null || true)
        if [[ "${idVendor}" == "${TARGET_VENDOR}" && "${idProduct}" == "${TARGET_PRODUCT}" ]]; then
            local block
            block=$(find "${dev}" -name "block" -type d 2>/dev/null | head -1)
            if [[ -n "${block}" ]]; then
                local bdev
                bdev=$(ls "${block}" 2>/dev/null | head -1)
                if [[ -n "${bdev}" ]]; then
                    echo "/dev/${bdev}"
                    return 0
                fi
            fi
        fi
    done
    return 1
}

# ---- main ----
echo "=== Android Image Flash Tool ==="
echo

if [[ ! -f "${IMAGE}" ]]; then
    echo "ERROR: Image not found: ${IMAGE}"
    echo "Usage: $0 [image.bin.gz]"
    exit 1
fi

IMAGE_SIZE=$(stat -c%s "${IMAGE}")
echo "Image : ${IMAGE} ($(numfmt --to=iec ${IMAGE_SIZE}))"

echo "Detecting SanDisk Extreme Pro (${TARGET_VENDOR}:${TARGET_PRODUCT})..."
if ! DEVICE=$(find_device); then
    echo "ERROR: SanDisk device not found. Is it plugged in?"
    exit 1
fi

echo "Target: ${DEVICE}"
echo
lsblk -o NAME,SIZE,MODEL,TRAN "${DEVICE}" 2>/dev/null || true
echo

read -r -p "WARNING: ALL DATA on ${DEVICE} will be ERASED. Continue? [yes/N] " confirm
if [[ "${confirm}" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

echo "Unmounting ${DEVICE} partitions..."
for part in "${DEVICE}"?*; do
    if mountpoint -q "${part}" 2>/dev/null; then
        sudo umount "${part}" && echo "  Unmounted ${part}"
    fi
done

echo
echo "Flashing ${IMAGE} -> ${DEVICE} ..."
echo
gzip -dc "${IMAGE}" | sudo dd of="${DEVICE}" bs=4M status=progress oflag=direct
sudo sync

echo
echo "Done! ${IMAGE} flashed to ${DEVICE}."
