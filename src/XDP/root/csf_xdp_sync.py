import time
import re
import os
from bcc import BPF

# Load the compiled XDP object file
b = BPF(obj="/root/xdp_csf.o")
blocked_ips = b.get_table("blocked_ips")
allowed_ports = b.get_table("allowed_ports")

def sync_csf_ports():
    """Reads CSF configuration and loads allowed ports into XDP."""
    allowed_ports.clear()
    
    # Always allow standard SSH port natively to avoid lockouts during sync
    allowed_ports[b.Backend.XDP_FLAGS(22)] = b.Backend.XDP_FLAGS(6) # TCP 22
    
    if not os.path.exists("/etc/csf/csf.conf"):
        return

    with open("/etc/csf/csf.conf", "r") as f:
        content = f.read()

    # Extract TCP_IN and UDP_IN port strings
    tcp_ports = re.search(r'^TCP_IN\s*=\s*"([^"]+)"', content, re.MULTILINE)
    udp_ports = re.search(r'^UDP_IN\s*=\s*"([^"]+)"', content, re.MULTILINE)

    if tcp_ports:
        for port in tcp_ports.group(1).split(','):
            if port.isdigit():
                allowed_ports[b.Backend.XDP_FLAGS(int(port))] = b.Backend.XDP_FLAGS(6) # 6 = TCP
                
    if udp_ports:
        for port in udp_ports.group(1).split(','):
            if port.isdigit():
                allowed_ports[b.Backend.XDP_FLAGS(int(port))] = b.Backend.XDP_FLAGS(17) # 17 = UDP

def sync_csf_denied_ips():
    """Reads csf.deny and updates the XDP blocklist map."""
    blocked_ips.clear()
    if not os.path.exists("/etc/csf/csf.deny"):
        return

    with open("/etc/csf/csf.deny", "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            
            # Simple IPv4 extraction (ignores comments at end of line)
            ip_match = re.match(r'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', line)
            if ip_match:
                ip_str = ip_match.group(1)
                # Convert IP string to network byte order integer
                import socket
                import struct
                ip_packed = socket.inet_aton(ip_str)
                ip_int = struct.unpack("I", ip_packed)[0]
                
                blocked_ips[b.Backend.XDP_FLAGS(ip_int)] = b.Backend.XDP_FLAGS(1)

print("Starting CSF to XDP synchronization daemon...")
while True:
    try:
        sync_csf_ports()
        sync_csf_denied_ips()
    except Exception as e:
        print(f"Sync Error: {e}")
    
    # Check for CSF updates every 10 seconds
    time.sleep(10)
