#!/bin/sh
# CLEANUP: Dynamic SSL Generator for CSF UI
# LOCATION: uninstall.d/01_dynamic_ssl.sh

UI_DIR="/etc/csf/ui"

echo "    > Removing dynamically generated SSL keys..."
rm -f "$UI_DIR/server.key"
rm -f "$UI_DIR/server.crt"
echo "    > SSL cleanup complete."