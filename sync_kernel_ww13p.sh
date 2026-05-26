#!/usr/bin/env bash
# =============================================================================
# Sync Kernel WW13_P source code
# Wiki: https://wiki.ith.intel.com/spaces/CACTUS/pages/4181529810/
# NOTE: WW13_P ALOS release uses WW13 Kernel release
# Kernel manifest: 2026WW13-Intel-Release-Kernel-Manifest.xml
#
# Usage: sync_kernel_ww13p.sh [OPTIONS]
#   -d, --dir    <path>   Kernel target directory (default: /root/kernel)
#   -j, --jobs   <num>    Parallel sync jobs      (default: 16)
#   -b, --branch <name>   Manifest repo branch    (default: mirror/14-Mar-2025)
#   -h, --help            Show this help
#
# Examples:
#   ./sync_kernel_ww13p.sh
#   ./sync_kernel_ww13p.sh --dir /data/kernel
#   ./sync_kernel_ww13p.sh -d /data/kernel -j 8
# =============================================================================
set -euo pipefail

KERNEL_DIR="${KERNEL_DIR:-/root/kernel}"
MANIFEST_URL="https://af01p-sc.devtools.intel.com/artifactory/android-ci-local/build/eng-builds/alos/one-ci/weekly/2026_WW13_P/2026WW13-Intel-Release-Kernel-Manifest.xml"
MANIFEST_FILE="2026WW13-Intel-Release-Kernel-Manifest.xml"
KERNEL_MANIFEST_BRANCH="${KERNEL_MANIFEST_BRANCH:-mirror/14-Mar-2025}"
SYNC_JOBS="${SYNC_JOBS:-16}"

# Parse CLI arguments
show_help() {
    sed -n '9,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            KERNEL_DIR="$2"; shift 2 ;;
        --dir=*)
            KERNEL_DIR="${1#*=}"; shift ;;
        -j|--jobs)
            SYNC_JOBS="$2"; shift 2 ;;
        --jobs=*)
            SYNC_JOBS="${1#*=}"; shift ;;
        -b|--branch)
            KERNEL_MANIFEST_BRANCH="$2"; shift 2 ;;
        --branch=*)
            KERNEL_MANIFEST_BRANCH="${1#*=}"; shift ;;
        -h|--help)
            show_help ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo "Run with --help for usage."
            exit 1 ;;
    esac
done

echo "======================================================"
echo " Kernel WW13_P Sync"
echo " Target dir : ${KERNEL_DIR}"
echo " Branch     : ${KERNEL_MANIFEST_BRANCH}"
echo " Sync jobs  : ${SYNC_JOBS}"
echo "======================================================"

# Artifactory credentials
if [[ -z "${AF_USER:-}" ]]; then
    read -rp "Artifactory username (Intel IDSID): " AF_USER
fi
if [[ -z "${AF_PASS:-}" ]]; then
    read -rsp "Artifactory password: " AF_PASS
    echo
fi

mkdir -p "${KERNEL_DIR}"
cd "${KERNEL_DIR}"

echo "[1/5] repo init (kernel manifest repo, branch: ${KERNEL_MANIFEST_BRANCH})..."
repo init -u https://github.com/intel-restricted/os.android.externalmirror.alos.kernel-manifest \
    -b "${KERNEL_MANIFEST_BRANCH}"

echo "[2/5] Downloading WW13 kernel manifest from Artifactory..."
wget --no-proxy --no-check-certificate \
    --user="${AF_USER}" --password="${AF_PASS}" \
    -O "${MANIFEST_FILE}" \
    "${MANIFEST_URL}"

echo "[3/5] Copying kernel manifest to .repo/manifests/..."
cp "${MANIFEST_FILE}" .repo/manifests/

echo "[4/5] repo init with WW13 kernel manifest..."
repo init -m "${MANIFEST_FILE}"

echo "[5/5] repo sync (-c -q -j${SYNC_JOBS})..."
repo sync -c -q -j"${SYNC_JOBS}"

echo "[LFS] Pulling LFS objects..."
repo forall -c "git lfs pull" || true

echo ""
echo "======================================================"
echo " Kernel WW13_P sync complete: ${KERNEL_DIR}"
echo "======================================================"
