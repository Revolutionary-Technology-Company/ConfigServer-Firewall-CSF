#!/bin/bash
# CLEANUP: XDP/eBPF Hardware Defense Node (u32 Math Translation)
# LOCATION: uninstall.d/06_xdp_u32_engine.sh

echo "    > Tearing down XDP u32 Hardware Defense Node..."

PRIMARY_IFACE=$(ip route get 8.8.8.8 | grep -oP '(?<=dev\s)\w+' | head -n 1)

if [ -n "$PRIMARY_IFACE" ]; then
    echo "    > Detaching u32 XDP layer from: $PRIMARY_IFACE"
    ip link set dev "$PRIMARY_IFACE" xdp off 2>/dev/null
fi

XDP_DIR="/usr/local/csf/xdp"
rm -f "$XDP_DIR/csf_u32_defense.c"
rm -f "$XDP_DIR/csf_u32_defense.o"

echo "    > u32 Hardware Defense Node successfully removed."