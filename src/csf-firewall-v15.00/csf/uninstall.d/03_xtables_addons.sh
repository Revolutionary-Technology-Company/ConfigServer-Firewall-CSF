#!/bin/bash
# CLEANUP: xtables-addons & MOK Secure Boot Enrollment
# LOCATION: uninstall.d/03_xtables_addons.sh

echo "    > Tearing down xtables-addons and MOK enrollment..."

# 1. Unload the modules from the live kernel
for mod in xt_TARPIT xt_CHAOS xt_DELUDE xt_ECHO xt_ACCOUNT; do
    rmmod "$mod" 2>/dev/null
done

# 2. Remove the packages based on OS
if [ -x "$(command -v dnf)" ]; then
    dnf remove -y xtables-addons > /dev/null 2>&1
elif [ -x "$(command -v apt-get)" ]; then
    apt-get remove -y xtables-addons-dkms > /dev/null 2>&1
fi

MOK_DIR="/root/.mok_keys"

# 3. Queue the MOK key for deletion from UEFI
if [ -f "$MOK_DIR/MOK.der" ]; then
    echo "    > Queuing MOK key for UEFI deletion. Password set to: csfroot"
    printf "csfroot\ncsfroot\n" | mokutil --delete "$MOK_DIR/MOK.der" > /dev/null 2>&1
    echo "    [!!!] NOTE: To completely wipe the key from UEFI hardware, you must reboot."
    echo "    [!!!] Select 'Delete MOK' at the blue screen and enter password: csfroot"
fi

# Delete the generated keys from the disk
rm -rf "$MOK_DIR"

# 4. Scrub the advertisements from csf.conf
CSF_CONF="/etc/csf/csf.conf"
if [ -f "$CSF_CONF" ]; then
    echo "    > Scrubbing xtables-addons targets from csf.conf..."
    sed -i '/# XTABLES-ADDONS TARGETS ENABLED/d' "$CSF_CONF"
    sed -i '/# You can now change DROP to: TARPIT, CHAOS, DELUDE, or ECHO/d' "$CSF_CONF"
    
    # Safely revert the active DROP target back to standard DROP if they were using an addon
    sed -i 's/^DROP = "TARPIT"/DROP = "DROP"/' "$CSF_CONF"
    sed -i 's/^DROP = "CHAOS"/DROP = "DROP"/' "$CSF_CONF"
    sed -i 's/^DROP = "DELUDE"/DROP = "DROP"/' "$CSF_CONF"
    sed -i 's/^DROP = "ECHO"/DROP = "DROP"/' "$CSF_CONF"
fi

echo "    > xtables-addons teardown complete."