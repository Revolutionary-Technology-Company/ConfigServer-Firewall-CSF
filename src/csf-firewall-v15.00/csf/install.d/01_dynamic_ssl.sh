#!/bin/sh
# FEATURE: Dynamic SSL Generator for CSF UI
# LOCATION: install.d/01_dynamic_ssl.sh

UI_DIR="/etc/csf/ui"

echo "    > Stripping baseline static SSL keys..."
rm -f "$UI_DIR/server.key"
rm -f "$UI_DIR/server.crt"

echo "    > Generating unique 4096-bit RSA key and SSL certificate..."
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
    -keyout "$UI_DIR/server.key" \
    -out "$UI_DIR/server.crt" \
    -subj "/C=US/ST=Washington/L=Seattle/O=Enterprise Security/OU=Firewall Node/CN=$(hostname)" \
    > /dev/null 2>&1

chmod 600 "$UI_DIR/server.key"
chmod 600 "$UI_DIR/server.crt"
echo "    > Dynamic UI SSL generation complete."