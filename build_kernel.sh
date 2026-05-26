#!/usr/bin/env bash
# =============================================================================
# Build Kernel WW13_P for Ocelot (A17 / 6.18)
# Wiki: https://wiki.ith.intel.com/spaces/CACTUS/pages/4181529810/
# Produces: bzImage, System.map, *.ko in out/kernel_x86_64/dist/
#           ocelot vendor modules in out/ocelot/dist/
#
# Usage: build_kernel.sh [OPTIONS]
#   -d, --dir  <path>   Kernel workspace directory (default: /root/kernel)
#   -j, --jobs <num>    Parallel build jobs         (default: system default)
#   -h, --help          Show this help
#
# Examples:
#   ./build_kernel.sh
#   ./build_kernel.sh --dir /data/kernel
#   ./build_kernel.sh -d /data/kernel
# =============================================================================
echo "kernel.apparmor_restrict_unprivileged_userns=0" | tee /etc/sysctl.d/60-apparmor-namespace.conf
sysctl --system

echo "====================================="
echo "验证配置是否生效："
sysctl kernel.apparmor_restrict_unprivileged_userns

set -euo pipefail

KERNEL_DIR="${KERNEL_DIR:-/root/kernel}"
BUILD_JOBS=""

# Parse CLI arguments
show_help() {
    sed -n '8,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            KERNEL_DIR="$2"; shift 2 ;;
        --dir=*)
            KERNEL_DIR="${1#*=}"; shift ;;
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

JOBS_FLAG=""
[[ -n "${BUILD_JOBS}" ]] && JOBS_FLAG="--jobs=${BUILD_JOBS}"

echo "======================================================"
echo " Kernel Build (A17 / 6.18, ocelot)"
echo " Kernel dir : ${KERNEL_DIR}"
[[ -n "${BUILD_JOBS}" ]] && echo " Build jobs : ${BUILD_JOBS}"
echo "======================================================"

cd "${KERNEL_DIR}"

echo "[1/2] Building common kernel (kernel_x86_64_dist)..."
tools/bazel run //common:kernel_x86_64_dist ${JOBS_FLAG}

echo "[2/2] Building ocelot device kernel (ocelot_dist)..."
tools/bazel run //private/devices/google/x86-64/intel/ocelot:ocelot_dist --config=ocelot ${JOBS_FLAG}

echo ""
echo "======================================================"
echo " Kernel build complete!"
echo " Outputs:"
echo "   ${KERNEL_DIR}/out/kernel_x86_64/dist/bzImage"
echo "   ${KERNEL_DIR}/out/kernel_x86_64/dist/System.map"
echo "   ${KERNEL_DIR}/out/kernel_x86_64/dist/*.ko  (system_dlkm)"
echo "   ${KERNEL_DIR}/out/ocelot/dist/*.ko          (vendor_dlkm)"
echo "======================================================"
