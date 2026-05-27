#!/usr/bin/env bash
# =============================================================================
# Deploy ALOS GRUB patches + Kernel patches
# Usage: ./deploy_patches.sh
#
# ALOS patches:   cd $ANDROID_BUILD_TOP && ./alos_grub/deploy.sh --target=<t>
# Kernel patches: patch-overlay -w <kernel_workspace> -p ./patches apply
# =============================================================================
set -euo pipefail

ALOS_GRUB_DIR="${ALOS_GRUB_DIR:-}"   # resolved interactively below

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $*"; }

echo "====================================================="
echo "  ALOS + Kernel Patch Deployer"
echo "====================================================="
echo ""

# -------------------------------------------------------
# Step 0: ALOS_GRUB_TOP
# -------------------------------------------------------
log_step "[0/3] alos-grub directory (ALOS_GRUB_TOP)"
if [[ -n "${ALOS_GRUB_DIR:-}" ]]; then
    log_info "Already set: ${ALOS_GRUB_DIR}"
    read -rp "  Use this path? [Y/n]: " confirm
    confirm="${confirm:-Y}"
    if [[ "${confirm,,}" != "y" ]]; then
        read -rp "  Enter path: " user_input
        ALOS_GRUB_DIR="${user_input}"
    fi
else
    read -rp "  Enter ALOS_GRUB_TOP path [/root/grub]: " user_input
    ALOS_GRUB_DIR="${user_input:-/root/grub}"
fi

if [[ ! -f "${ALOS_GRUB_DIR}/deploy.sh" ]]; then
    log_error "deploy.sh not found in '${ALOS_GRUB_DIR}'"
    exit 1
fi
log_info "ALOS_GRUB_TOP = ${ALOS_GRUB_DIR}"

PATCH_OVERLAY="${ALOS_GRUB_DIR}/kernel/patch-overlay"
KERNEL_PATCHES="${ALOS_GRUB_DIR}/kernel/patches"

# -------------------------------------------------------
# Step 1: ANDROID_BUILD_TOP
# -------------------------------------------------------
log_step "[1/3] Android source tree (ANDROID_BUILD_TOP)"
if [[ -n "${ANDROID_BUILD_TOP:-}" ]]; then
    log_info "Already set: ${ANDROID_BUILD_TOP}"
    read -rp "  Use this path? [Y/n]: " confirm
    confirm="${confirm:-Y}"
    if [[ "${confirm,,}" != "y" ]]; then
        read -rp "  Enter path: " user_input
        ANDROID_BUILD_TOP="${user_input}"
    fi
else
    read -rp "  Enter ANDROID_BUILD_TOP path [/root/alos]: " user_input
    ANDROID_BUILD_TOP="${user_input:-/root/alos}"
fi

export ANDROID_BUILD_TOP

if [[ ! -f "${ANDROID_BUILD_TOP}/build/envsetup.sh" ]]; then
    log_error "Cannot find build/envsetup.sh in '${ANDROID_BUILD_TOP}'"
    exit 1
fi
log_info "ANDROID_BUILD_TOP = ${ANDROID_BUILD_TOP}"

# -------------------------------------------------------
# Step 2: Kernel workspace
# -------------------------------------------------------
log_step "[2/3] Kernel workspace"
read -rp "  Enter kernel workspace path [/root/kernel]: " kernel_input
KERNEL_WORKSPACE="${kernel_input:-/root/kernel}"

if [[ ! -d "${KERNEL_WORKSPACE}" ]]; then
    log_error "Kernel workspace not found: ${KERNEL_WORKSPACE}"
    exit 1
fi
log_info "KERNEL_WORKSPACE = ${KERNEL_WORKSPACE}"

# -------------------------------------------------------
# Step 3: Target device
# -------------------------------------------------------
log_step "[3/3] Target device"
echo "  Available targets:"
echo "    1) ocelot  - Wildcat Lake, ChromeOS-EC"
echo "    2) firefly - Wildcat Lake, Windows-EC (inherits ocelot)"
echo "    3) fatcat  - Panther Lake (PTL)"
read -rp "  Enter target [ocelot]: " target_input
TARGET_DEVICE="${target_input:-ocelot}"

case "${TARGET_DEVICE}" in
    1) TARGET_DEVICE="ocelot" ;;
    2) TARGET_DEVICE="firefly" ;;
    3) TARGET_DEVICE="fatcat" ;;
    ocelot|firefly|fatcat) ;;
    *)
        log_error "Invalid target: ${TARGET_DEVICE}"
        exit 1
        ;;
esac
log_info "Target device = ${TARGET_DEVICE}"
echo ""

# -------------------------------------------------------
# Part A: Apply ALOS patches via deploy.sh
# -------------------------------------------------------
log_step "[A] Deploying ALOS patches (aosp_diff + prebuilts)..."

if [[ ! -f "${ALOS_GRUB_DIR}/deploy.sh" ]]; then
    log_error "deploy.sh not found: ${ALOS_GRUB_DIR}/deploy.sh"
    exit 1
fi

cd "${ANDROID_BUILD_TOP}"
bash "${ALOS_GRUB_DIR}/deploy.sh" --target="${TARGET_DEVICE}"
log_info "ALOS patches deployed."
echo ""

# -------------------------------------------------------
# Part B: Apply kernel patches via patch-overlay
# -------------------------------------------------------
log_step "[B] Applying kernel patches via patch-overlay..."

if [[ ! -x "${PATCH_OVERLAY}" ]]; then
    log_error "patch-overlay not found or not executable: ${PATCH_OVERLAY}"
    exit 1
fi

if [[ ! -d "${KERNEL_PATCHES}" ]]; then
    log_error "Kernel patches dir not found: ${KERNEL_PATCHES}"
    exit 1
fi

cd "${ALOS_GRUB_DIR}/kernel"
./patch-overlay -w "${KERNEL_WORKSPACE}" -p ./patches apply
log_info "Kernel patches applied."
echo ""

echo "====================================================="
echo "  All done!"
echo "  ALOS patches  -> ${ANDROID_BUILD_TOP}/vendor/intel/utils/aosp_diff/${TARGET_DEVICE}/"
echo "  Prebuilts     -> ${ANDROID_BUILD_TOP}/vendor/intel/utils/grub_prebuilts/"
echo "  Kernel patches-> ${KERNEL_WORKSPACE}"
echo "====================================================="
