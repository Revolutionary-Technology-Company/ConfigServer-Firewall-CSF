#!/bin/bash
# FEATURE: Google Safe Browsing (GSB) API Threat Poller
# LOCATION: install.d/09_gsb_poller.sh

echo "    > Initializing Google Safe Browsing Threat Poller..."

# 1. Install dependencies for API interaction
if [ -x "$(command -v dnf)" ]; then
    dnf install -y curl jq > /dev/null 2>&1
elif [ -x "$(command -v apt-get)" ]; then
    apt-get install -y curl jq > /dev/null 2>&1
fi

BIN_DIR="/usr/local/csf/bin"
CONF_DIR="/etc/csf"
mkdir -p "$BIN_DIR"

POLLER_SCRIPT="$BIN_DIR/rt-gsb-poller.sh"
GSB_CONF="$CONF_DIR/rt_gsb.conf"
SERVICE_FILE="/etc/systemd/system/rt-gsb-poller.service"
TIMER_FILE="/etc/systemd/system/rt-gsb-poller.timer"

# 2. Create the API Configuration File (User must add key later)
if [ ! -f "$GSB_CONF" ]; then
    cat << 'EOF' > "$GSB_CONF"
# Revolutionary Technology - GSB API Configuration
# Get your key from: https://console.cloud.google.com/apis/library/safebrowsing.googleapis.com
GSB_API_KEY="INSERT_YOUR_GOOGLE_API_KEY_HERE"
GSB_ENABLE="0" # Change to 1 to activate poller
EOF
    chmod 600 "$GSB_CONF"
fi

# 3. Generate the Poller Script
cat << 'EOF' > "$POLLER_SCRIPT"
#!/bin/bash
# Scans temporary bans and queries Google Safe Browsing API.
# If Google flags the IP as malicious, it is permanently banned.

source /etc/csf/rt_gsb.conf
if [ "$GSB_ENABLE" != "1" ] || [ "$GSB_API_KEY" == "INSERT_YOUR_GOOGLE_API_KEY_HERE" ]; then
    exit 0
fi

TEMP_BANS="/var/lib/csf/csf.tempban"
if [ ! -f "$TEMP_BANS" ]; then exit 0; fi

# Extract unique IPs from temp bans
awk -F'|' '{print $1}' "$TEMP_BANS" | sort | uniq | while read -r IP; do
    
    # Format the JSON payload for Google API v4
    PAYLOAD=$(cat <<JSON
{
  "client": {
    "clientId": "rt-csf-firewall",
    "clientVersion": "1.0.0"
  },
  "threatInfo": {
    "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE", "POTENTIALLY_HARMFUL_APPLICATION"],
    "platformTypes": ["ANY_PLATFORM"],
    "threatEntryTypes": ["IP_RANGE"],
    "threatEntries": [
      {"url": "$IP"}
    ]
  }
}
JSON
)

    # Query Google API
    RESPONSE=$(curl -s -X POST "https://safebrowsing.googleapis.com/v4/threatMatches:find?key=$GSB_API_KEY" \
         -H "Content-Type: application/json" \
         -d "$PAYLOAD")

    # If the API returns a match array, Google has flagged this IP
    if echo "$RESPONSE" | jq -e '.matches' > /dev/null; then
        echo "[GSB] Threat confirmed by Google for IP: $IP. Upgrading to permanent hardware ban."
        # Remove from temp ban
        csf -tr "$IP" > /dev/null 2>&1
        # Add to permanent ban with GSB documentation
        csf -d "$IP" "Google Safe Browsing Confirmed Threat (Auto-Upgraded)" > /dev/null 2>&1
    fi
done
EOF

chmod 700 "$POLLER_SCRIPT"

# 4. Generate the Systemd Service
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=RT Google Safe Browsing Poller
After=network.target

[Service]
Type=oneshot
ExecStart=$POLLER_SCRIPT
EOF

# 5. Generate the Systemd Timer (Runs every 15 minutes)
cat << EOF > "$TIMER_FILE"
[Unit]
Description=Run RT GSB Poller every 15 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
Unit=rt-gsb-poller.service

[Install]
WantedBy=timers.target
EOF

# 6. Enable and Start the Timer
systemctl daemon-reload >/dev/null 2>&1
systemctl enable rt-gsb-poller.timer >/dev/null 2>&1
systemctl start rt-gsb-poller.timer >/dev/null 2>&1

echo "    > GSB Poller installed. Add API key to /etc/csf/rt_gsb.conf to activate."