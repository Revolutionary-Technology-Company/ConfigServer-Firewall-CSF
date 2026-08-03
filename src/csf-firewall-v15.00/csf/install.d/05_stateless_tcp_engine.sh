#!/bin/bash
# FEATURE: Pure Stateless TCP Defense & Cryptographic SYN Cookies
# LOCATION: install.d/05_stateless_tcp_engine.sh

echo "    > Initializing Pure Stateless TCP Defense Engine..."

# 1. Stateless Kernel Hardening (Zero-State Overhead)
SYSCTL_CONF="/etc/sysctl.d/99-csf-stateless.conf"

cat << 'EOF' > "$SYSCTL_CONF"
# Enterprise DDoS Mitigation: Pure Stateless Parameters
# Force strict SYN Cookies (Stateless mathematical handshakes)
net.ipv4.tcp_syncookies = 1

# Maximize queues for raw packet handling
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535

# Drop connections faster (stateless mindset)
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_fin_timeout = 10

# Disable generic TCP metrics tracking
net.ipv4.tcp_no_metrics_save = 1

# Disable loose conntrack (if any other ports accidentally trigger it)
net.netfilter.nf_conntrack_tcp_loose = 0
EOF

sysctl -p "$SYSCTL_CONF" > /dev/null 2>&1

# 2. Create the CSF Hook for Stateless Raw Injection
POST_HOOK_DIR="/usr/local/include/csf/post.d"
mkdir -p "$POST_HOOK_DIR"
STATELESS_HOOK="$POST_HOOK_DIR/05_stateless_tcp.sh"

cat << 'EOF' > "$STATELESS_HOOK"
#!/bin/sh
# Inject Pure Stateless Defense into the Raw Table
IPTABLES=$(which iptables)

# 1. UNTRACK TARGET PORTS (80, 443)
# Bypasses the nf_conntrack memory allocation completely for web traffic.
$IPTABLES -t raw -I PREROUTING -p tcp -m multiport --dports 80,443 -j NOTRACK
$IPTABLES -t raw -I OUTPUT -p tcp -m multiport --sports 80,443 -j NOTRACK

# 2. STATELESS RAW DROPS (Shred invalid packets before routing)
# Drop packets missing the SYN flag if they are the first packet seen
$IPTABLES -t raw -A PREROUTING -p tcp ! --syn -m state --state NEW -j DROP

# Drop impossible TCP flag combinations statelessly
$IPTABLES -t raw -A PREROUTING -p tcp --tcp-flags ALL NONE -j DROP
$IPTABLES -t raw -A PREROUTING -p tcp --tcp-flags ALL ALL -j DROP
$IPTABLES -t raw -A PREROUTING -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
$IPTABLES -t raw -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
$IPTABLES -t raw -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
$IPTABLES -t raw -A PREROUTING -p tcp --tcp-flags ACK,FIN FIN -j DROP
$IPTABLES -t raw -A PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP
$IPTABLES -t raw -A PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP
EOF

chmod 755 "$STATELESS_HOOK"

echo "    > Pure Stateless Engine applied. Connection tracking bypassed for web ports."