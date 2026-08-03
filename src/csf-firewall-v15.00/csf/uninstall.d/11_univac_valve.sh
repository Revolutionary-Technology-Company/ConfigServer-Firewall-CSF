#!/bin/bash
# CLEANUP: UNIVAC & Aviation Airgap Isolation Valve
# LOCATION: uninstall.d/11_univac_valve.sh

echo "    > Tearing down UNIVAC Airgap Valve..."

BIN_DIR="/usr/local/csf/bin"
VALVE_SCRIPT="$BIN_DIR/csf_isolation_valve.py"
GLOBAL_LINK="/usr/local/bin/univac-valve"

# 1. Remove the Python script
rm -f "$VALVE_SCRIPT"

# 2. Remove the global command link
rm -f "$GLOBAL_LINK"

echo "    > UNIVAC Airgap Valve removed successfully. (Existing airgap states remain active)."