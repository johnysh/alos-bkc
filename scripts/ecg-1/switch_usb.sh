#!/bin/bash

RELAY_NAME=$(usbrelay |& tail -n 1 |awk -F '=' '{print $1}')

sudo usbrelay $RELAY_NAME=0 && sleep 1 && usbrelay $RELAY_NAME=1 && sleep 0.5 && usbrelay $RELAY_NAME=0
