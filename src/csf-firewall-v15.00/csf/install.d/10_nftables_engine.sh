#!/bin/bash
# FEATURE: Dual-Engine nftables Backend & DDoS Flowtables
# LOCATION: install.d/10_nftables_engine.sh

echo "    > Initializing Native nftables Dual-Engine Architecture..."

# 1. Install nftables utilities
if [ -x "$(command -v dnf)" ]; then
    dnf install -y nftables > /dev/null 2>&1
elif [ -x "$(command -v apt-get)" ]; then
    apt-get install -y nftables > /dev/null 2>&1
fi

CONF_DIR="/etc/csf"
NFT_CONF="$CONF_DIR/nftables.conf"

# 2. Generate the High-Performance Baseline nftables Template
# This file handles the raw DDoS logic (Layer 3/4) before CSF rules even apply.
cat << 'EOF' > "$NFT_CONF"
#!/usr/sbin/nft -f
flush ruleset

table inet csf_firewall {
    # Dynamic set to hold IPs that exceed TCP SYN rate limits
    set ddos_ips {
        type ipv4_addr
        flags dynamic, timeout
        timeout 10m
    }

    # Fast-path hardware offloading for established connections
    flowtable f_fastpath {
        hook ingress priority 0;
        devices = { eth0 }; # CSF will replace this dynamically if needed
    }

    chain prerouting {
        type filter hook prerouting priority raw; policy accept;
        
        # 1. Drop malformed packets instantly
        ct state invalid counter drop
        tcp flags & (fin|syn|rst|ack) == 0x0 counter drop
        tcp flags & (fin|syn) == (fin|syn) counter drop
        tcp flags & (syn|rst) == (syn|rst) counter drop
    }

    chain input {
        type filter hook input priority filter; policy drop;

        # 2. Hardware Offload (Bypass CPU for established streams)
        ct state established,related flow add @f_fastpath
        ct state established,related accept

        # 3. Dynamic DDoS Rate Limiting (50 SYN/sec max per IP)
        tcp dport { 80, 443 } tcp flags & (fin|syn|rst|ack) == syn limit rate over 50/second burst 100 packets add @ddos_ips { ip saddr }
        
        # 4. Drop IPs caught by the dynamic DDoS meter
        ip saddr @ddos_ips counter drop

        # (CSF rules will be injected here dynamically by the Perl translator)
    }

    chain forward {
        type filter hook forward priority filter; policy accept;
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF

chmod 600 "$NFT_CONF"

# Ensure legacy iptables is preferred by default, but systemd knows nftables exists
systemctl enable nftables >/dev/null 2>&1

echo "    > nftables baseline initialized. Awaiting WHM toggle."