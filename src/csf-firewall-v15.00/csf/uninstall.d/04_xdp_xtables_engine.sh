#!/bin/bash
# CLEANUP: XDP/eBPF Hardware Offload Engine
# LOCATION: uninstall.d/04_xdp_xtables_engine.sh

echo "    > Tearing down XDP eBPF Hardware Engine..."

# 1. Find the primary network interface dynamically
PRIMARY_IFACE=$(ip route get 8.8.8.8 | grep -oP '(?<=dev\s)\w+' | head -n 1)

# 2. Detach the XDP program from the kernel/NIC
if [ -n "$PRIMARY_IFACE" ]; then
    echo "    > Detaching XDP from interface: $PRIMARY_IFACE"
    ip link set dev "$PRIMARY_IFACE" xdp off 2>/dev/null
fi

# 3. Clean up compiler artifacts and source files
XDP_DIR="/usr/local/csf/xdp"
rm -f "$XDP_DIR/csf_xdp_xtables.c"
rm -f "$XDP_DIR/csf_xdp_xtables.o"

# Remove directory if empty
rmdir "$XDP_DIR" 2>/dev/null

echo "    > XDP Hardware Engine successfully removed."