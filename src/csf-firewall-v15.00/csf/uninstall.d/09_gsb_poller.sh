#!/bin/bash
# CLEANUP: Google Safe Browsing (GSB) API Threat Poller
# LOCATION: uninstall.d/09_gsb_poller.sh

echo "    > Tearing down Google Safe Browsing Poller..."

BIN_DIR="/usr/local/csf/bin"
CONF_DIR="/etc/csf"

POLLER_SCRIPT="$BIN_DIR/rt-gsb-poller.sh"
GSB_CONF="$CONF_DIR/rt_gsb.conf"
SERVICE_FILE="/etc/systemd/system/rt-gsb-poller.service"
TIMER_FILE="/etc/systemd/system/rt-gsb-poller.timer"

# 1. Stop and disable the timer and service
if systemctl is-active --quiet rt-gsb-poller.timer; then
    systemctl stop rt-gsb-poller.timer >/dev/null 2>&1
fi
systemctl disable rt-gsb-poller.timer >/dev/null 2>&1
systemctl stop rt-gsb-poller.service >/dev/null 2>&1

# 2. Remove systemd files
rm -f "$TIMER_FILE"
rm -f "$SERVICE_FILE"
systemctl daemon-reload >/dev/null 2>&1

# 3. Remove the scripts and configuration
rm -f "$POLLER_SCRIPT"

# Note: We prompt before deleting the config file in case it contains a paid API key
if [ -f "$GSB_CONF" ]; then
    echo "    > Removed GSB Poller logic. Retaining $GSB_CONF to protect API key."
    # If you want to force delete it anyway, uncomment the next line:
    # rm -f "$GSB_CONF"
fi

echo "    > Google Safe Browsing integration successfully removed."