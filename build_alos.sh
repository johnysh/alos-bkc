#!/usr/bin/env bash
# =============================================================================
# Build ALOS WW13_P (ocelot-cl3b-userdebug)
# Wiki: https://wiki.ith.intel.com/spaces/CACTUS/pages/4181529810/
# Produces: droid -> replace kernel -> pack-image
#
# Usage: build_alos.sh [OPTIONS]
#   -a, --alos-dir   <path>   Android source root  (default: /root/alos)
#   -k, --kernel-dir <path>   Kernel workspace root (default: /root/kernel)
#   -j, --jobs       <num>    Parallel build jobs   (default: 40)
#   -h, --help                Show this help
#
# Examples:
#   ./build_alos.sh
#   ./build_alos.sh --alos-dir /data/alos --kernel-dir /data/kernel
#   ./build_alos.sh -a /data/alos -k /data/kernel -j 16
# =============================================================================
echo "kernel.apparmor_restrict_unprivileged_userns=0" | tee /etc/sysctl.d/60-apparmor-namespace.conf
sysctl --system

echo "====================================="
echo "check whether affect："
sysctl kernel.apparmor_restrict_unprivileged_userns

set -euo pipefail

# Defaults (env var or hardcoded fallback)
ALOS_DIR="${ALOS_DIR:-/root/alos}"
BUILD_JOBS="${BUILD_JOBS:-40}"
KERNEL_REPO="${KERNEL_REPO:-/root/kernel}"

# Parse CLI arguments
show_help() {
    sed -n '8,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--alos-dir)
            ALOS_DIR="$2"; shift 2 ;;
        --alos-dir=*)
            ALOS_DIR="${1#*=}"; shift ;;
        -k|--kernel-dir)
            KERNEL_REPO="$2"; shift 2 ;;
        --kernel-dir=*)
            KERNEL_REPO="${1#*=}"; shift ;;
        -j|--jobs)
            BUILD_JOBS="$2"; shift 2 ;;
        --jobs=*)
            BUILD_JOBS="${1#*=}"; shift ;;
        -h|--help)
            show_help ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo "Run with --help for usage."
            exit 1 ;;
    esac
done

echo "======================================================"
echo " ALOS Build"
echo " Source dir  : ${ALOS_DIR}"
echo " Kernel repo : ${KERNEL_REPO}"
echo " Build jobs  : ${BUILD_JOBS}"
echo "======================================================"

cd "${ALOS_DIR}"

echo "[1/5] Set BOARD=ocelot and source build/envsetup.sh..."
export BOARD=ocelot
source build/envsetup.sh

echo "[2/5] Running APK prebuilt recipe script..."
bash +x vendor/google_shared/packages/desktop/ApkTempPrebuilts/arsp-apks-prebuilt-recipe.sh

echo "[3/5] lunch ocelot-cl3b-userdebug..."
lunch ocelot-cl3b-userdebug

echo "[4/5] Building droid (j${BUILD_JOBS})..."
SOONG_RUN_CIPD_PROXY_SERVER=false USE_RBE=false m droid -j"${BUILD_JOBS}"

# -------------------------------------------------------
# Replace kernel binaries before pack-image
# -------------------------------------------------------
echo ""
echo "[4.5] Replacing kernel binaries from ${KERNEL_REPO}..."

KERNEL_DEST="${ALOS_DIR}/device/google/desktop/ocelot-kernels/6.18/legacy_kernel_internal"

if [[ ! -d "${KERNEL_DEST}" ]]; then
    echo "ERROR: kernel destination not found: ${KERNEL_DEST}"
    echo "       Make sure you are in the correct ALOS workspace."
    exit 1
fi

# Verify kernel build outputs exist
for f in \
    "${KERNEL_REPO}/out/kernel_x86_64/dist/bzImage" \
    "${KERNEL_REPO}/out/kernel_x86_64/dist/System.map"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Kernel output not found: $f"
        echo "       Run build_kernel.sh first."
        exit 1
    fi
done

pushd "${KERNEL_DEST}"

echo "  Replacing bzImage and System.map..."
rm -f bzImage System.map
cp "${KERNEL_REPO}/out/kernel_x86_64/dist/bzImage" bzImage
cp "${KERNEL_REPO}/out/kernel_x86_64/dist/System.map" System.map

echo "  Replacing system_dlkm/*.ko..."
rm -rf system_dlkm; mkdir -p system_dlkm
cp "${KERNEL_REPO}/out/kernel_x86_64/dist/"*.ko system_dlkm/

echo "  Replacing vendor_dlkm/*.ko..."
rm -rf vendor_dlkm; mkdir -p vendor_dlkm
cp "${KERNEL_REPO}/out/ocelot/dist/"*.ko vendor_dlkm/

popd

echo "  Kernel binaries replaced successfully."
echo "    bzImage    : $(du -h ${KERNEL_DEST}/bzImage | cut -f1)"
echo "    system_dlkm: $(ls ${KERNEL_DEST}/system_dlkm/*.ko 2>/dev/null | wc -l) modules"
echo "    vendor_dlkm: $(ls ${KERNEL_DEST}/vendor_dlkm/*.ko 2>/dev/null | wc -l) modules"

# -------------------------------------------------------
echo ""
echo "[5/5] Packing image..."
SOONG_RUN_CIPD_PROXY_SERVER=false USE_RBE=false m pack-image -j"${BUILD_JOBS}"

echo ""
echo "======================================================"
echo " ALOS build complete!"
echo " Output: ${ALOS_DIR}/out/target/product/ocelot/"
echo "======================================================"
