#!/bin/bash
RULE='SUBSYSTEM=="hidraw", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="05df", MODE="0666"'
echo "$RULE" | sudo tee /etc/udev/rules.d/99-usbrelay.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
sleep 1
echo "=== usbrelay output ==="
usbrelay 2>&1
