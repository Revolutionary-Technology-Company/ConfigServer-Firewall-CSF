#!/bin/sh
# CLEANUP: ModSecurity 3.x JSON to LFD Log Bridge
# LOCATION: uninstall.d/02_modsec3_bridge.sh

echo "    > Tearing down ModSecurity 3.x Hybrid Bridge..."

BIN_DIR="/usr/local/csf/bin"
BRIDGE_SCRIPT="$BIN_DIR/modsec3_converter.pl"
SERVICE_FILE="/etc/systemd/system/modsec3-converter.service"
BRIDGE_LOG="/var/log/modsec_lfd_bridge.log"

# 1. Stop and remove the service
if systemctl is-active --quiet modsec3-converter.service; then
    systemctl stop modsec3-converter.service >/dev/null 2>&1
fi
systemctl disable modsec3-converter.service >/dev/null 2>&1
rm -f "$SERVICE_FILE"
systemctl daemon-reload >/dev/null 2>&1

# 2. Remove the Perl script and intermediate logs
rm -f "$BRIDGE_SCRIPT"
rm -f "$BRIDGE_LOG"

# 3. Clean the path out of csf.conf (Leaves Legacy ModSec2 untouched)
if grep -q "$BRIDGE_LOG" /etc/csf/csf.conf; then
    sed -i "s| $BRIDGE_LOG||g" /etc/csf/csf.conf
    sed -i "s|$BRIDGE_LOG ||g" /etc/csf/csf.conf
fi

echo "    > ModSecurity 3.x Bridge removed successfully."