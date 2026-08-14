#include <linux/bpf.h>
#include <linux/in.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <bpf/bpf_helpers.h>

// Map 1: Dynamic IP Blocklist (holds IPs CSF wants to block)
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 65536);
    __type(key, __be32);   // IPv4 Address
    __type(value, __u32);  // Placeholder (1 = Block)
} blocked_ips SEC(".maps");

// Map 2: Allowed Ports List (holds TCP/UDP ports CSF allows)
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1024);
    __type(key, __u16);    // Port number
    __type(value, __u32);  // Protocol (6 = TCP, 17 = UDP)
} allowed_ports SEC(".maps");

SEC("xdp")
int xdp_csf_sync(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;

    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) return XDP_PASS;

    // We are only processing IPv4 traffic here
    if (eth->h_proto == __constant_htons(ETH_P_IP)) {
        struct iphdr *iph = (void *)(eth + 1);
        if ((void *)(iph + 1) > data_end) return XDP_PASS;

        // 1. Check if the incoming Source IP is in CSF's blocklist
        __u32 *blocked = bpf_map_lookup_elem(&blocked_ips, &iph->saddr);
        if (blocked) {
            return XDP_DROP; 
        }

        // 2. Parse Layer 4 protocols to enforce CSF Allowed Ports
        __u16 dest_port = 0;
        __u32 proto = iph->protocol;

        if (proto == IPPROTO_TCP) {
            struct tcphdr *tcp = (void *)(iph + 1);
            if ((void *)(tcp + 1) > data_end) return XDP_PASS;
            dest_port = __constant_ntohs(tcp->dest);
        } else if (proto == IPPROTO_UDP) {
            struct udphdr *udp = (void *)(iph + 1);
            if ((void *)(udp + 1) > data_end) return XDP_PASS;
            dest_port = __constant_ntohs(udp->dest);
        } else {
            // Let ICMP and other non-TCP/UDP traffic pass to nftables
            return XDP_PASS;
        }

        // 3. Check if the port is explicitly allowed for this protocol
        __u32 *allowed_proto = bpf_map_lookup_elem(&allowed_ports, &dest_port);
        if (!allowed_proto || *allowed_proto != proto) {
            return XDP_DROP; // Port is not in CSF allow list! Drop it.
        }
    }

    return XDP_PASS; // Send safe traffic up to nftables
}

char _license[] SEC("license") = "GPL";
