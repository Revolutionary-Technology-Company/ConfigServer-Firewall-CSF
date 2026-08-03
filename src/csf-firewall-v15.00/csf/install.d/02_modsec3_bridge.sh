#!/bin/sh
# FEATURE: ModSecurity 3.x JSON to LFD Log Bridge
# LOCATION: install.d/02_modsec3_bridge.sh

echo "    > Initializing ModSecurity 3.x Hybrid Bridge..."

BIN_DIR="/usr/local/csf/bin"
BRIDGE_SCRIPT="$BIN_DIR/modsec3_converter.pl"
SERVICE_FILE="/etc/systemd/system/modsec3-converter.service"
BRIDGE_LOG="/var/log/modsec_lfd_bridge.log"

# Create the log file so LFD doesn't fail if it starts before the converter
touch "$BRIDGE_LOG"
chmod 600 "$BRIDGE_LOG"

# 1. Generate the Perl JSON-to-Legacy Converter
cat << 'EOF' > "$BRIDGE_SCRIPT"
#!/usr/bin/perl
# Flatten ModSecurity 3 JSON into Legacy ModSecurity 2 strings for LFD
use strict;
use warnings;

$| = 1; # Force autoflush for real-time LFD detection

my $source_log = $ARGV[0] || '/var/log/modsec_audit.log';
my $dest_log   = $ARGV[1] || '/var/log/modsec_lfd_bridge.log';

# Fallback creation if source doesn't exist yet
unless (-e $source_log) {
    open(my $touch, '>>', $source_log);
    close($touch);
}

open(my $in, '-|', "tail", "-F", $source_log) or die "Cannot tail $source_log: $!";
open(my $out, '>>', $dest_log) or die "Cannot write $dest_log: $!";

while(my $line = <$in>) {
    # Extract IP, Rule ID, and Message from standard ModSec3 JSON
    if ($line =~ /"client_ip":"([^"]+)".*"ruleId":"?(\d+)"?.*"msg":"([^"]+)"/) {
        my ($ip, $id, $msg) = ($1, $2, $3);
        # Output in legacy ModSec2 format that LFD's native regex expects
        print $out "[client $ip] ModSecurity: Warning. Pattern match ... [id \"$id\"] [msg \"$msg\"]\n";
    }
}
EOF

chmod 700 "$BRIDGE_SCRIPT"

# 2. Generate the Systemd Service
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=ConfigServer ModSecurity 3.x JSON Converter
After=network.target

[Service]
Type=simple
# Watches standard JSON log and outputs to the Bridge Log
ExecStart=/usr/bin/perl $BRIDGE_SCRIPT /var/log/modsec_audit.log $BRIDGE_LOG
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 3. Enable and start the converter service
systemctl daemon-reload >/dev/null 2>&1
systemctl enable modsec3-converter.service >/dev/null 2>&1
systemctl restart modsec3-converter.service >/dev/null 2>&1

# 4. Safely append to csf.conf to preserve Legacy ModSecurity 2
# This ensures lfd watches both old and new formats simultaneously.
if grep -q "^MODSEC_LOG =" /etc/csf/csf.conf; then
    # Only append if it's not already in the string
    if ! grep -q "$BRIDGE_LOG" /etc/csf/csf.conf; then
        sed -i "s|^MODSEC_LOG = \"\(.*\)\"|MODSEC_LOG = \"\1 $BRIDGE_LOG\"|" /etc/csf/csf.conf
    fi
fi

echo "    > ModSecurity 3.x Bridge active. Legacy ModSecurity 2 preserved."