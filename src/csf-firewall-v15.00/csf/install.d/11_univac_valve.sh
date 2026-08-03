#!/bin/bash
# FEATURE: UNIVAC & Aviation Airgap Isolation Valve
# LOCATION: install.d/11_univac_valve.sh

echo "    > Initializing UNIVAC Airgap Valve..."

BIN_DIR="/usr/local/csf/bin"
mkdir -p "$BIN_DIR"
VALVE_SCRIPT="$BIN_DIR/csf_isolation_valve.py"
GLOBAL_LINK="/usr/local/bin/univac-valve"

# 1. Generate the Hardened Python Utility
cat << 'EOF' > "$VALVE_SCRIPT"
#!/usr/bin/env python3
import sys
import os
import subprocess
import argparse
import ipaddress

class CSFAirgapValve:
    def __init__(self, univac_ip: str, aviation_ip: str):
        # Strict IP Validation to prevent command injection
        try:
            self.univac_ip = str(ipaddress.ip_address(univac_ip))
            self.aviation_ip = str(ipaddress.ip_address(aviation_ip))
        except ValueError:
            print("[!] FATAL: Invalid IP Address format provided.")
            sys.exit(1)

    def isolate_univac(self) -> bool:
        # Applies block silently without triggering lock contention (no csf -r)
        subprocess.run(["csf", "-d", self.univac_ip, "UNIVAC_AIRGAP_LOCKED"], check=False, stdout=subprocess.DEVNULL)
        return True

    def authorize_univac(self) -> bool:
        subprocess.run(["csf", "-ar", self.univac_ip], check=False, stdout=subprocess.DEVNULL)
        subprocess.run(["csf", "-a", self.univac_ip, "UNIVAC_UPLINK_AUTHORIZED"], check=False, stdout=subprocess.DEVNULL)
        return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="CSF Airgap Valve")
    parser.add_argument("--univac", required=True, help="UNIVAC IP Address")
    parser.add_argument("--aviation", required=True, help="Aviation IP Address")
    parser.add_argument("--action", choices=["isolate", "authorize"], required=True)
    args = parser.parse_args()

    # Fork to background instantly to prevent daemon hangups
    if os.fork() != 0:
        sys.exit(0) 

    valve = CSFAirgapValve(univac_ip=args.univac, aviation_ip=args.aviation)
    
    if args.action == "isolate":
        valve.isolate_univac()
    elif args.action == "authorize":
        valve.authorize_univac()
EOF

# 2. Secure and Link
chmod 700 "$VALVE_SCRIPT"
ln -sf "$VALVE_SCRIPT" "$GLOBAL_LINK"

echo "    > UNIVAC Valve installed. Accessible globally via command: univac-valve"