#!/bin/bash
# ==============================================================================
# FEATURE: XDP/eBPF Hardware Offload Engine for xtables-addons targets
# DESCRIPTION: Unified Installer & Uninstaller (Includes TCP Reflection Security Patch)
# USAGE: ./04_xdp_xtables_engine.sh [install|uninstall]
# ==============================================================================

XDP_DIR="/usr/local/csf/xdp"
XDP_SRC="$XDP_DIR/csf_xdp_xtables.c"
XDP_OBJ="$XDP_DIR/csf_xdp_xtables.o"

install_module() {
    echo "    > Initializing XDP eBPF Hardware Engine Installation..."

    # 1. Install LLVM/Clang eBPF toolchain
    if [ -x "$(command -v dnf)" ]; then
        dnf install -y clang llvm libbpf libbpf-devel bpftool iproute > /dev/null 2>&1
    elif [ -x "$(command -v apt-get)" ]; then
        apt-get update > /dev/null 2>&1
        apt-get install -y clang llvm libbpf-dev linux-tools-common linux-tools-$(uname -r) bpftool iproute2 > /dev/null 2>&1
    fi

    # 2. Setup Directories
    mkdir -p "$XDP_DIR"

    # 3. Generate the Advanced eBPF C Code (With Security Patch)
    cat << 'EOF' > "$XDP_SRC"
#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <linux/in.h>
#include <bpf/bpf_helpers.h>

#define ACTION_DROP   0
#define ACTION_TARPIT 1
#define ACTION_ECHO   2
#define ACTION_CHAOS  3
#define ACTION_DELUDE 4

// The blocklist map populated by CSF (Key: IP, Value: Action ID)
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 100000);
    __type(key, __u32);
    __type(value, __u32);
} blocked_ips SEC(".maps");

// Helper to swap MAC addresses for XDP_TX bounce
static __always_inline void swap_mac(struct ethhdr *eth) {
    __u8 tmp[ETH_ALEN];
    __builtin_memcpy(tmp, eth->h_source, ETH_ALEN);
    __builtin_memcpy(eth->h_source, eth->h_dest, ETH_ALEN);
    __builtin_memcpy(eth->h_dest, tmp, ETH_ALEN);
}

// Helper to swap IPs for XDP_TX bounce
static __always_inline void swap_ip(struct iphdr *iph) {
    __u32 tmp = iph->saddr;
    iph->saddr = iph->daddr;
    iph->daddr = tmp;
}

SEC("xdp_csf_engine")
int rt_xdp_xtables_firewall(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;

    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) return XDP_PASS;

    if (eth->h_proto != __constant_htons(ETH_P_IP)) return XDP_PASS;

    struct iphdr *iph = (void *)(eth + 1);
    if ((void *)(iph + 1) > data_end) return XDP_PASS;
    if (iph->ihl < 5) return XDP_DROP;

    // Check if the source IP is in our blocklist
    __u32 *action = bpf_map_lookup_elem(&blocked_ips, &iph->saddr);
    if (!action) return XDP_PASS; // Not blocked, let OS handle it

    __u32 current_action = *action;

    // If CHAOS, randomize the action between TARPIT, ECHO, and DELUDE
    if (current_action == ACTION_CHAOS) {
        current_action = (bpf_get_prandom_u32() % 3) + 1; 
    }

    if (current_action == ACTION_DROP) {
        return XDP_DROP;
    }

    // --- XDP_TX BOUNCE LOGIC (SECURITY PATCHED) ---
    struct tcphdr *tcph = NULL;
    if (iph->protocol == IPPROTO_TCP) {
        tcph = (void *)iph + (iph->ihl * 4);
        if ((void *)(tcph + 1) > data_end) return XDP_DROP;
        
        swap_mac(eth);
        swap_ip(iph);
        
        __u16 tmp_port = tcph->source;
        tcph->source = tcph->dest;
        tcph->dest = tmp_port;

        if (current_action == ACTION_TARPIT) {
            tcph->ack = 1; tcph->syn = 0; tcph->rst = 0; tcph->window = 0;
        } else if (current_action == ACTION_DELUDE) {
            tcph->rst = 1; tcph->syn = 0; tcph->ack = 0;
        }
        return XDP_TX; // Valid TCP, bounce it!
    }

    // SECURITY FIX: If it was not TCP (e.g., UDP/ICMP), do NOT bounce it. 
    // Hard drop to prevent malformed reflection attacks on your NIC.
    return XDP_DROP; 
}

char _license[] SEC("license") = "GPL";
EOF

    echo "    > Compiling eBPF XDP Engine via Clang..."
    clang -O2 -g -Wall -target bpf -c "$XDP_SRC" -o "$XDP_OBJ"

    # 4. Find the primary network interface dynamically
    PRIMARY_IFACE=$(ip route get 8.8.8.8 | grep -oP '(?<=dev\s)\w+' | head -n 1)

    if [ -n "$PRIMARY_IFACE" ]; then
        echo "    > Attaching XDP Engine to interface: $PRIMARY_IFACE"
        # Remove any existing XDP program first
        ip link set dev "$PRIMARY_IFACE" xdp off 2>/dev/null
        
        # Attach the new compiled object
        ip link set dev "$PRIMARY_IFACE" xdp obj "$XDP_OBJ" sec xdp_csf_engine
        echo "    > [SUCCESS] XDP Hardware Engine successfully hooked."
    else
        echo "    [!] Warning: Could not detect primary interface. XDP attachment failed."
    fi
}

uninstall_module() {
    echo "    > Tearing down XDP eBPF Hardware Engine..."

    # 1. Find the primary network interface dynamically
    PRIMARY_IFACE=$(ip route get 8.8.8.8 | grep -oP '(?<=dev\s)\w+' | head -n 1)

    # 2. Detach the XDP program from the kernel/NIC
    if [ -n "$PRIMARY_IFACE" ]; then
        echo "    > Detaching XDP from interface: $PRIMARY_IFACE"
        ip link set dev "$PRIMARY_IFACE" xdp off 2>/dev/null
    fi

    # 3. Clean up compiler artifacts and source files
    rm -f "$XDP_SRC"
    rm -f "$XDP_OBJ"

    # Remove directory if empty
    rmdir "$XDP_DIR" 2>/dev/null

    echo "    > [SUCCESS] XDP Hardware Engine successfully removed."
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