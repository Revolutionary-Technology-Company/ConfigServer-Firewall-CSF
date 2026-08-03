#!/bin/bash
# CLEANUP: RT QCSuper & Baseband Threat Detector Daemon
# LOCATION: uninstall.d/07_qcsuper_detector.sh

echo "    > Tearing down QCSuper Threat Detector..."

BIN_DIR="/usr/local/csf/bin"
DETECTOR_SCRIPT="$BIN_DIR/rt_qcsuper_detector.py"
SERVICE_FILE="/etc/systemd/system/rt-qcsuper-detector.service"

# 1. Stop and disable the background daemon
if systemctl is-active --quiet rt-qcsuper-detector.service; then
    systemctl stop rt-qcsuper-detector.service >/dev/null 2>&1
fi
systemctl disable rt-qcsuper-detector.service >/dev/null 2>&1

# 2. Delete the service file
rm -f "$SERVICE_FILE"
systemctl daemon-reload >/dev/null 2>&1

# 3. Delete the Python executable
rm -f "$DETECTOR_SCRIPT"

# 4. Safely unlock any serial interfaces that might have been hard-locked by the daemon
for dev in ttyUSB0 ttyUSB1 ttyS0 ttyACM0; do
    if [ -e "/dev/$dev" ]; then
        # Restore standard root/dialout permissions
        chmod 660 "/dev/$dev" 2>/dev/null
    fi
done

echo "    > QCSuper Threat Detector successfully removed."