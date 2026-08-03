#!/bin/bash
# CLEANUP: Pure Stateless TCP Defense & Cryptographic SYN Cookies
# LOCATION: uninstall.d/05_stateless_tcp_engine.sh

echo "    > Tearing down Pure Stateless TCP Engine..."

# 1. Remove the sysctl configuration and reset defaults
SYSCTL_CONF="/etc/sysctl.d/99-csf-stateless.conf"
if [ -f "$SYSCTL_CONF" ]; then
    rm -f "$SYSCTL_CONF"
    sysctl -w net.ipv4.tcp_syncookies=1 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_max_syn_backlog=1024 > /dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=1000 > /dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_tcp_loose=1 > /dev/null 2>&1
fi

# 2. Clean up the CSF Hook
POST_HOOK_DIR="/usr/local/include/csf/post.d"
STATELESS_HOOK="$POST_HOOK_DIR/05_stateless_tcp.sh"
rm -f "$STATELESS_HOOK"

# 3. Flush the live stateless rules from the raw table
IPTABLES=$(which iptables)

# Remove NOTRACK rules
while $IPTABLES -t raw -D PREROUTING -p tcp -m multiport --dports 80,443 -j NOTRACK 2>/dev/null; do :; done
while $IPTABLES -t raw -D OUTPUT -p tcp -m multiport --sports 80,443 -j NOTRACK 2>/dev/null; do :; done

# Remove Stateless flag drops
while $IPTABLES -t raw -D PREROUTING -p tcp ! --syn -m state --state NEW -j DROP 2>/dev/null; do :; done
while $IPTABLES -t raw -D PREROUTING -p tcp --tcp-flags ALL NONE -j DROP 2>/dev/null; do :; done
while $IPTABLES -t raw -D PREROUTING -p tcp --tcp-flags ALL ALL -j DROP 2>/dev/null; do :; done
while $IPTABLES -t raw -D PREROUTING -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP 2>/dev/null; do :; done
while $IPTABLES -t raw -D PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP 2>/dev/null; do :; done
while $IPTABLES -t raw -D PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP 2>/dev/null; do :; done
while $IPTABLES -t raw -D PREROUTING -p tcp --tcp-flags ACK,FIN FIN -j DROP 2>/dev/null; do :; done
while $IPTABLES -t raw -D PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP 2>/dev/null; do :; done
while $IPTABLES -t raw -D PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP 2>/dev/null; do :; done

echo "    > Pure Stateless Engine successfully removed."