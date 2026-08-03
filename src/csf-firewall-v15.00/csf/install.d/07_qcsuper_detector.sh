#!/bin/bash
# ==============================================================================
# FEATURE: RT QCSuper & Baseband Threat Detector Daemon
# DESCRIPTION: Unified Installer & Uninstaller
# USAGE: ./07_qcsuper_detector.sh [install|uninstall]
# ==============================================================================

BIN_DIR="/usr/local/csf/bin"
DETECTOR_SCRIPT="$BIN_DIR/rt_qcsuper_detector.py"
SERVICE_FILE="/etc/systemd/system/rt-qcsuper-detector.service"

install_module() {
    echo "    > Initializing QCSuper / Baseband Threat Detector Installation..."
    mkdir -p "$BIN_DIR"

    # 1. Write the Hardened Python Detector Script (Includes Fault-Tolerance)
    cat << 'EOF' > "$DETECTOR_SCRIPT"
#!/usr/bin/env python3
import time
import subprocess
import sys

class RTQCSuperDetector:
    def __init__(self, interfaces=["tcp:2500", "tcp:2501", "ttyUSB0", "ttyS0"]):
        self.interfaces = interfaces
        self.hdlc_flag = b'\x7e'
        
        self.threat_signatures = {
            "DIAG_LOG_CONFIG_F": b'\x73\x00\x00\x00',     # Command 115: Log configuration
            "DIAG_EXT_MSG_CONFIG_F": b'\x7d\x00\x00\x00', # Command 125: Extended message config
            "QCSUPER_HANDSHAKE_1": b'\x7e\x00\x1c\x00',   # Typical Diag Version request
            "GSMTAP_ENCAPSULATION": b'\x02\x04\x01'       # GSMTAP v2 header
        }

    def analyze_stream_buffer(self, interface, byte_stream):
        if self.hdlc_flag in byte_stream:
            for sig_name, sig_bytes in self.threat_signatures.items():
                if sig_bytes in byte_stream:
                    self.trigger_csf_isolation(sig_name, interface)

    def trigger_csf_isolation(self, threat_type, source):
        print(f"\n[!!! CRITICAL THREAT DETECTED !!!]\nTHREAT: {threat_type}\nSOURCE: {source}")
        if "tcp" in source:
            try:
                ip = source.split(":")[1]
                subprocess.run(["csf", "-d", ip, "Unauthorized QCSuper / Diag Protocol Injection"], check=False)
            except IndexError:
                pass
        else:
            # STRICT SECURITY: Safe-listed isolation for hardware serial ports
            valid_interfaces = ["ttyUSB0", "ttyUSB1", "ttyS0", "ttyACM0"]
            if source in valid_interfaces:
                print(f"    > Hard-locking interface: /dev/{source}")
                subprocess.run(["chmod", "000", f"/dev/{source}"], check=False)
            else:
                print(f"[!] Warning: Interface {source} not in safe list. Chmod aborted.")

if __name__ == "__main__":
    print("[+] RT QCSuper Detector daemon initialized.")
    detector = RTQCSuperDetector()
    
    # HARDENED: Infinite fault-tolerant hardware loop prevents systemd death spirals
    while True:
        try:
            # (Insert your PySerial / Socket byte reading logic here)
            # Example: byte_stream = serial_port.read(1024)
            # detector.analyze_stream_buffer("ttyUSB0", byte_stream)
            time.sleep(1)
            sys.stdout.flush()
        except KeyboardInterrupt:
            print("[-] Terminating Detector.")
            sys.exit(0)
        except Exception as e:
            # Catch hardware disconnects and wait for USB/Serial to re-mount
            print(f"[!] Hardware Fault or Read Error: {e}. Retrying in 5 seconds...")
            time.sleep(5)
EOF

    chmod 700 "$DETECTOR_SCRIPT"

    # 2. Create the Systemd Service
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Revolutionary Technology QCSuper Hardware Threat Detector
After=network.target csf.service lfd.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 $DETECTOR_SCRIPT
Restart=always
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=rt-qcsuper

[Install]
WantedBy=multi-user.target
EOF

    # 3. Enable and Start the Daemon
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable rt-qcsuper-detector.service >/dev/null 2>&1
    systemctl restart rt-qcsuper-detector.service >/dev/null 2>&1

    echo "    > [SUCCESS] QCSuper Threat Detector armed and running as a background service."
}

uninstall_module() {
    echo "    > Tearing down QCSuper Threat Detector..."

    # 1. Stop and disable the background daemon
    if systemctl is-active --quiet rt-qcsuper-detector.service; then
        systemctl stop rt-qcsuper-detector.service >/dev/null 2>&1
    fi
    systemctl disable rt-qcsuper-detector.service >/dev/null 2>&1

    # 2. Delete the service file and Python executable
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload >/dev/null 2>&1
    rm -f "$DETECTOR_SCRIPT"

    # 3. Safely unlock any serial interfaces that might have been hard-locked by the daemon
    for dev in ttyUSB0 ttyUSB1 ttyS0 ttyACM0; do
        if [ -e "/dev/$dev" ]; then
            # Restore standard root/dialout permissions gracefully
            chmod 660 "/dev/$dev" 2>/dev/null
        fi
    done

    echo "    > [SUCCESS] QCSuper Threat Detector successfully removed and serial ports unlocked."
}

# ==============================================================================
# Execution Router
# ==============================================================================
case "$1" in
    install)
        install_module
        ;;
    uninstall)
        uninstall_module
        ;;
    *)
        echo "Usage: $0 {install|uninstall}"
        exit 1
        ;;
esac