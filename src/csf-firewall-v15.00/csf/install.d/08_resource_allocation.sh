#!/bin/bash
# FEATURE: Hardware Resource Allocation (12% Compute, 12% RAM, 5% Cache)
# LOCATION: install.d/08_resource_allocation.sh

echo "    > Initializing Dedicated Hardware Resource Allocation..."

# 1. Enable Multicore Processing & Kernel Offloading
# Forces CSF to offload blocklists to the kernel's multicore ipset engine 
# rather than processing them single-threaded in iptables.
sed -i 's/^LF_IPSET = .*/LF_IPSET = "1"/' /etc/csf/csf.conf

# 2. Systemd Cgroups V2 Setup (12% RAM, 12% CPU)
# CPUQuota is calculated per-core. 12% of total CPU = (Cores * 12)%
CORES=$(nproc)
CPU_QUOTA=$(( CORES * 12 ))

SYSTEMD_DIR="/etc/systemd/system/lfd.service.d"
mkdir -p "$SYSTEMD_DIR"

cat << EOF > "$SYSTEMD_DIR/override.conf"
[Service]
# Enable multicore task distribution for LFD child processes
TasksMax=infinity

# Hard limit: 12% of TOTAL server compute capability
CPUQuota=${CPU_QUOTA}%

# Hard limit: 12% of TOTAL system RAM
MemoryMax=12%
MemoryHigh=10%
EOF

systemctl daemon-reload >/dev/null 2>&1

# 3. Dedicated RAM Cache (tmpfs - 5% of System RAM)
# LFD aggressively reads/writes to /var/lib/csf for IP tracking. 
# We move this entire directory into the server's RAM.
if ! grep -q "/var/lib/csf" /etc/fstab; then
    echo "    > Building 5% Volatile RAM Cache for tracking databases..."
    
    # Backup existing data before mounting over it
    cp -a /var/lib/csf /var/lib/csf_backup
    
    # Mount the 5% tmpfs in fstab so it survives reboots
    echo "tmpfs /var/lib/csf tmpfs rw,size=5%,uid=0,gid=0,mode=0700 0 0" >> /etc/fstab
    mount /var/lib/csf
    
    # Restore the data directly into the RAM cache
    cp -a /var/lib/csf_backup/* /var/lib/csf/ 2>/dev/null
    rm -rf /var/lib/csf_backup
fi

# Restart the daemon to apply limits
systemctl restart lfd >/dev/null 2>&1

echo "    > Resources locked: 12% CPU, 12% RAM, 5% Cache. Multicore enabled."