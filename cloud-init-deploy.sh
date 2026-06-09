#!/bin/bash
set -e

echo "=================================================="
echo " Starting Cloud-Init Alpine VPN GRUB Injection "
echo "=================================================="

ISO_FILE="/root/alpine-vpn.iso"
if [ ! -f "$ISO_FILE" ]; then
    echo "Error: $ISO_FILE not found."
    exit 1
fi

# 1. Mount the custom ISO
ISO_MNT="/tmp/mnt_iso"
mkdir -p "$ISO_MNT"
mount -o loop,ro "$ISO_FILE" "$ISO_MNT"

# 2. Copy boot files to the host's existing /boot partition
echo "[*] Copying Alpine boot files to host /boot..."
cp "$ISO_MNT/boot/vmlinuz-virt" "/boot/"
cp "$ISO_MNT/boot/initramfs-virt" "/boot/"
cp "$ISO_MNT/boot/modloop-virt" "/boot/"
cp "$ISO_MNT/localhost.apkovl.tar.gz" "/boot/"

# Clean up ISO mount
umount "$ISO_MNT"
rm -rf "$ISO_MNT"

# 3. Detect UUID of the host's /boot directory partition
BOOT_PART=$(df -P /boot | tail -1 | awk '{print $1}')
BOOT_UUID=$(blkid -s UUID -o value "$BOOT_PART")
echo "✔ Detected /boot partition UUID: $BOOT_UUID"

# 4. Insert Custom Alpine entry to GRUB 40_custom
echo "[*] Adding Alpine entry to GRUB..."
GRUB_CUSTOM="/etc/grub.d/40_custom"

# Backup original 40_custom
cp "$GRUB_CUSTOM" "${GRUB_CUSTOM}.bak"

# Append Alpine boot configuration
cat <<EOF >> "$GRUB_CUSTOM"

menuentry "Alpine Linux RAM-only VPN" --class gnu-linux --class gnu --class os {
    insmod part_gpt
    insmod part_msdos
    insmod ext2
    insmod xfs
    insmod btrfs
    search --no-floppy --fs-uuid --set=root $BOOT_UUID
    linux /boot/vmlinuz-virt alpine_dev=UUID=$BOOT_UUID apkovl=UUID=$BOOT_UUID:/boot/localhost.apkovl.tar.gz modloop=UUID=$BOOT_UUID:/boot/modloop-virt console=tty0 console=ttyS0,115200
    initrd /boot/initramfs-virt
}
EOF

# 5. Set Alpine as the default GRUB boot entry
echo "[*] Configuring GRUB default to Alpine..."
if [ -f "/etc/default/grub" ]; then
    # Change GRUB_DEFAULT to point to our menu entry name
    sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="Alpine Linux RAM-only VPN"/' /etc/default/grub
fi

# 6. Update GRUB configuration on the host
echo "[*] Updating GRUB bootloader..."
if command -v update-grub &>/dev/null; then
    update-grub
elif command -v grub2-mkconfig &>/dev/null; then
    if [ -f "/boot/grub2/grub.cfg" ]; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    elif [ -f "/boot/efi/EFI/ubuntu/grub.cfg" ]; then
        grub2-mkconfig -o /boot/efi/EFI/ubuntu/grub.cfg
    else
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
else
    echo "Warning: Could not find update-grub or grub2-mkconfig. Please update GRUB manually."
fi

echo "=================================================="
echo "✔ INJECTION COMPLETE! Rebooting in 5 seconds..."
echo "=================================================="
sleep 5
reboot
