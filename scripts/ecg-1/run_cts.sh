#!/bin/bash
export PATH=~/sjh/android-cts/tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 确保设备连接
ADB_DEVICE="10.239.58.115:5555"
echo "[*] Connecting to device $ADB_DEVICE..."
adb connect $ADB_DEVICE
sleep 2
adb devices

echo "[*] Starting CTS..."
cd ~/sjh/android-cts/tools
./cts-tradefed "$@"
