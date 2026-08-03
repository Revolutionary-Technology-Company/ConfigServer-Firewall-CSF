#!/bin/bash
# CLEANUP: Hardware Resource Allocation
# LOCATION: uninstall.d/08_resource_allocation.sh

echo "    > Tearing down Hardware Resource Allocations..."

# 1. Remove Systemd Cgroups limits
SYSTEMD_DIR="/etc/systemd/system/lfd.service.d"
if [ -f "$SYSTEMD_DIR/override.conf" ]; then
    rm -f "$SYSTEMD_DIR/override.conf"
    rmdir "$SYSTEMD_DIR" 2>/dev/null
    systemctl daemon-reload >/dev/null 2>&1
fi

# 2. Unmount RAM Cache and restore to physical disk
if grep -q "tmpfs /var/lib/csf" /etc/fstab; then
    echo "    > Flushing 5% RAM cache to physical disk..."
    
    # Back up the RAM data to the physical disk temporarily
    cp -a /var/lib/csf /var/lib/csf_backup
    
    # Unmount the RAM disk
    umount /var/lib/csf
    
    # Remove from fstab
    sed -i '\@tmpfs /var/lib/csf tmpfs@d' /etc/fstab
    
    # Write the data back to the standard hard drive
    cp -a /var/lib/csf_backup/* /var/lib/csf/ 2>/dev/null
    rm -rf /var/lib/csf_backup
fi

# 3. Disable ipset kernel offloading (Optional, but strict reversal)
sed -i 's/^LF_IPSET = .*/LF_IPSET = "0"/' /etc/csf/csf.conf

# Restart the daemon to release limits
systemctl restart lfd >/dev/null 2>&1

echo "    > Hardware limits removed. Disk I/O restored to physical drive."