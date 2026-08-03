#!/bin/bash
# FEATURE: XDP/eBPF Hardware Defense Node (u32 Math Translation)
# LOCATION: install.d/06_xdp_u32_engine.sh

echo "    > Initializing XDP u32 Hardware Defense Node..."

# 1. Install LLVM/Clang eBPF toolchain if missing
if [ -x "$(command -v dnf)" ]; then
    dnf install -y clang llvm libbpf libbpf-devel bpftool iproute > /dev/null 2>&1
elif [ -x "$(command -v apt-get)" ]; then
    apt-get install -y clang llvm libbpf-dev bpftool iproute2 > /dev/null 2>&1
fi

XDP_DIR="/usr/local/csf/xdp"
mkdir -p "$XDP_DIR"
XDP_SRC="$XDP_DIR/csf_u32_defense.c"
XDP_OBJ="$XDP_DIR/csf_u32_defense.o"

# 2. Generate the Advanced eBPF C Code (Translating your bash script)
cat << 'EOF' > "$XDP_SRC"
#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <linux/in.h>
#include <bpf/bpf_helpers.h>

SEC("xdp_u32_engine")
int rt_xdp_u32_firewall(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;

    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) return XDP_PASS;
    if (eth->h_proto != __constant_htons(ETH_P_IP)) return XDP_PASS;

    struct iphdr *iph = (void *)(eth + 1);
    if ((void *)(iph + 1) > data_end) return XDP_PASS;

    // ======================================================================
    // RULE 1 & 2: IP MALFORMED & ANTI-SPOOFING (From u32 Layer 3)
    // ======================================================================
    // Bash: iptables -m u32 --u32 "0 & 0x0F000000 < 0x50000000"
    if (iph->ihl < 5) return XDP_DROP;

    // Bash: iptables -m u32 --u32 "0 & 0xFF000000 = 0x0A000000" (Drop 10.0.0.0/8 ingress)
    // We bitwise AND the source IP with the 255.0.0.0 subnet mask
    if ((iph->saddr & __constant_htonl(0x000000FF)) == __constant_htonl(0x0000000A)) {
        return XDP_DROP; 
    }

    // Locate the start of the Transport Layer safely
    void *trans_data = (void *)iph + (iph->ihl * 4);
    if (trans_data > data_end) return XDP_PASS;

    // ======================================================================
    // RULE 3: UDP REFLECTION FLOODS (From u32 Layer 7)
    // ======================================================================
    if (iph->protocol == IPPROTO_UDP) {
        struct udphdr *udph = trans_data;
        if ((void *)(udph + 1) > data_end) return XDP_PASS;

        // NTP Amplification Check (Port 123)
        if (udph->dest == __constant_htons(123) || udph->source == __constant_htons(123)) {
            __u8 *payload = (void *)(udph + 1);
            // Bash: "0 >> 22 & 0x3C @ 8 = 0x2A000000" (Check if first payload byte is 0x2a / MON_GETLIST)
            if ((void *)(payload + 1) <= data_end) {
                if (payload[0] == 0x2A) {
                    return XDP_DROP; // Instant hardware shred
                }
            }
        }
        return XDP_PASS;
    }

    // ======================================================================
    // RULE 4: TCP STATE & FLAG MITIGATION (From Layer 4)
    // ======================================================================
    if (iph->protocol == IPPROTO_TCP) {
        struct tcphdr *tcph = trans_data;
        if ((void *)(tcph + 1) > data_end) return XDP_PASS;

        // Bash: Drop Null Flag Attacks (--tcp-flags ALL NONE)
        if (!tcph->syn && !tcph->ack && !tcph->fin && !tcph->rst && !tcph->psh && !tcph->urg) {
            return XDP_DROP;
        }

        // Drop XMAS Tree Attacks (FIN, PSH, URG all set)
        if (tcph->fin && tcph->psh && tcph->urg) {
            return XDP_DROP;
        }

        // Drop SYN-FIN packets (Impossible state used by scanners)
        if (tcph->syn && tcph->fin) {
            return XDP_DROP;
        }
    }

    return XDP_PASS; 
}

char _license[] SEC("license") = "GPL";
EOF

echo "    > Compiling eBPF u32 Math Engine via Clang..."
clang -O2 -g -Wall -target bpf -c "$XDP_SRC" -o "$XDP_OBJ"

PRIMARY_IFACE=$(ip route get 8.8.8.8 | grep -oP '(?<=dev\s)\w+' | head -n 1)

if [ -n "$PRIMARY_IFACE" ]; then
    echo "    > Attaching u32 Hardware Defense Node to: $PRIMARY_IFACE"
    ip link set dev "$PRIMARY_IFACE" xdp off 2>/dev/null
    ip link set dev "$PRIMARY_IFACE" xdp obj "$XDP_OBJ" sec xdp_u32_engine
    echo "    > Hardware u32 Mathematics applied directly to NIC."
else
    echo "    [!] Warning: Primary interface detection failed."
fi