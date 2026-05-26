#!/usr/bin/env bash
# =============================================================================
# Sync ALOS WW13_P source code
# Wiki: https://wiki.ith.intel.com/spaces/CACTUS/pages/4181529810/
# WW13_P manifest: manifest-alos-2026_WW13_P-manifest_with_gms-generated.xml
#
# Usage: sync_alos_ww13p.sh [OPTIONS]
#   -d, --dir  <path>   ALOS target directory (default: /root/alos)
#   -j, --jobs <num>    Parallel sync jobs    (default: 16)
#   -h, --help          Show this help
#
# Examples:
#   ./sync_alos_ww13p.sh
#   ./sync_alos_ww13p.sh --dir /data/alos
#   ./sync_alos_ww13p.sh -d /data/alos -j 8
# =============================================================================
set -euo pipefail

ALOS_DIR="${ALOS_DIR:-/root/alos}"
MANIFEST_URL="https://af01p-sc.devtools.intel.com/artifactory/android-ci-local/build/eng-builds/alos/one-ci/weekly/2026_WW13_P/manifest-alos-2026_WW13_P-manifest_with_gms-generated.xml"
MANIFEST_FILE="manifest-alos-2026_WW13_P-manifest_with_gms-generated.xml"
SYNC_JOBS="${SYNC_JOBS:-16}"

# Parse CLI arguments
show_help() {
    sed -n '8,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            ALOS_DIR="$2"; shift 2 ;;
        --dir=*)
            ALOS_DIR="${1#*=}"; shift ;;
        -j|--jobs)
            SYNC_JOBS="$2"; shift 2 ;;
        --jobs=*)
            SYNC_JOBS="${1#*=}"; shift ;;
        -h|--help)
            show_help ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo "Run with --help for usage."
            exit 1 ;;
    esac
done

echo "======================================================"
echo " ALOS WW13_P Sync"
echo " Target dir : ${ALOS_DIR}"
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

mkdir -p "${ALOS_DIR}"
cd "${ALOS_DIR}"

echo "[1/5] repo init (base manifest)..."
repo init -u https://github.com/intel-innersource/os.android.bsp.client-manifests \
    -b main -m default_with_gms.xml

echo "[2/5] Downloading WW13_P weekly manifest from Artifactory..."
wget --no-proxy --no-check-certificate \
    --user="${AF_USER}" --password="${AF_PASS}" \
    -O "${MANIFEST_FILE}" \
    "${MANIFEST_URL}"

echo "[3/5] Copying manifest to .repo/manifests/..."
cp "${MANIFEST_FILE}" .repo/manifests/

echo "[4/5] repo init with WW13_P manifest..."
repo init -m "${MANIFEST_FILE}"

echo "[5/5] repo sync (-c -q -j${SYNC_JOBS})..."
repo sync -c -q -j"${SYNC_JOBS}"

echo "[LFS] Pulling LFS objects (1 repo may report lfs error - expected)..."
repo forall -p -v -c 'git lfs pull' || true

echo ""
echo "======================================================"
echo " ALOS WW13_P sync complete: ${ALOS_DIR}"
echo "======================================================"
