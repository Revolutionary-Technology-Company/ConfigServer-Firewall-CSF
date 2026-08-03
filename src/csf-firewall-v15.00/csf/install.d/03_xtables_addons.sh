#!/bin/bash
# FEATURE: xtables-addons & ESET-style MOK Secure Boot Enrollment
# LOCATION: install.d/03_xtables_addons.sh

echo "    > Initializing xtables-addons installation and Secure Boot MOK enrollment..."

# 1. Install Dependencies based on OS
if [ -x "$(command -v dnf)" ]; then
    dnf install -y epel-release dkms kernel-devel kernel-headers openssl mokutil
    dnf install -y xtables-addons
elif [ -x "$(command -v apt-get)" ]; then
    apt-get update
    apt-get install -y xtables-addons-dkms linux-headers-$(uname -r) openssl mokutil
fi

MOK_DIR="/root/.mok_keys"
mkdir -p "$MOK_DIR"

# 2. Generate the MOK Key (ESET-style)
if [ ! -f "$MOK_DIR/MOK.priv" ]; then
    echo "    > Generating new RSA Machine Owner Key (MOK) for kernel signing..."
    openssl req -new -x509 -newkey rsa:2048 -keyout "$MOK_DIR/MOK.priv" \
        -outform DER -out "$MOK_DIR/MOK.der" -nodes -days 36500 \
        -subj "/C=US/ST=Washington/L=Seattle/O=Enterprise Security/OU=Firewall Node/CN=CSF_Xtables_MOK" \
        > /dev/null 2>&1
fi

# 3. Locate the kernel sign-file script
SIGN_FILE=""
if [ -f "/usr/src/kernels/$(uname -r)/scripts/sign-file" ]; then
    SIGN_FILE="/usr/src/kernels/$(uname -r)/scripts/sign-file" # RHEL/Alma
elif [ -f "/usr/src/linux-headers-$(uname -r)/scripts/sign-file" ]; then
    SIGN_FILE="/usr/src/linux-headers-$(uname -r)/scripts/sign-file" # Ubuntu/Debian
fi

# 4. Sign the xtables-addons modules (TARPIT, CHAOS, DELUDE, ECHO, etc.)
if [ -n "$SIGN_FILE" ]; then
    echo "    > Cryptographically signing xtables-addons (.ko) modules..."
    for mod in $(find /lib/modules/$(uname -r) -type f -name "xt_*.ko"); do
        "$SIGN_FILE" sha256 "$MOK_DIR/MOK.priv" "$MOK_DIR/MOK.der" "$mod"
    done
else
    echo "    [!] Warning: Kernel sign-file script not found. Skipping module signing."
fi

# 5. Enroll the MOK into UEFI
# NOTE: mokutil requires a temporary password for the next reboot. We use "csfroot".
if mokutil --test-key "$MOK_DIR/MOK.der" 2>&1 | grep -q "is not enrolled"; then
    echo "    > Enrolling MOK to UEFI. Password set to: csfroot"
    printf "csfroot\ncsfroot\n" | mokutil --import "$MOK_DIR/MOK.der"
    echo "    [!!!] ACTION REQUIRED: You MUST reboot this server."
    echo "    [!!!] Upon reboot, a blue MOKManager screen will appear."
    echo "    [!!!] Select 'Enroll MOK', continue, and enter the password: csfroot"
fi

# 6. Update csf.conf to advertise the new DROP targets
echo "    > Advertising TARPIT, CHAOS, DELUDE, and ECHO in csf.conf..."
CSF_CONF="/etc/csf/csf.conf"

# Remove any previous injection to prevent duplicates
sed -i '/# XTABLES-ADDONS TARGETS ENABLED/d' "$CSF_CONF"
sed -i '/# You can now change DROP to: TARPIT, CHAOS, DELUDE, or ECHO/d' "$CSF_CONF"

# Inject the documentation right above the DROP setting
sed -i '/^DROP =/i # XTABLES-ADDONS TARGETS ENABLED\n# You can now change DROP to: TARPIT, CHAOS, DELUDE, or ECHO' "$CSF_CONF"

echo "    > xtables-addons installation complete. Targets are ready."