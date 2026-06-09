#!/bin/bash
set -e

# Memeriksa argumen disk
DISK="$1"
if [ -z "$DISK" ]; then
    echo "Penggunaan: sudo ./install.sh <target-disk>"
    echo "Contoh: sudo ./install.sh /dev/sda"
    exit 1
fi

# Memastikan dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Harap jalankan skrip ini sebagai root (sudo)."
    exit 1
fi

# Memvalidasi apakah disk target ada
if [ ! -b "$DISK" ]; then
    echo "Error: Disk target '$DISK' tidak ditemukan atau bukan block device."
    exit 1
fi

echo "=================================================="
echo "   Alpine RAM-only VPN Installer (SystemRescue)   "
echo "=================================================="
echo "PERINGATAN: Semua data di disk '$DISK' akan DIHAPUS!"
read -p "Apakah Anda yakin ingin melanjutkan? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    echo "Instalasi dibatalkan."
    exit 0
fi

ISO_FILE="./alpine-vpn.iso"
if [ ! -f "$ISO_FILE" ]; then
    echo "Error: Berkas '$ISO_FILE' tidak ditemukan di direktori saat ini."
    echo "Harap pastikan Anda telah menyalin berkas 'alpine-vpn.iso' ke sini."
    exit 1
fi

# 1. Menentukan nama partisi (menangani partisi NVMe seperti /dev/nvme0n1p1 vs /dev/sda1)
if [[ "$DISK" =~ "nvme" ]]; then
    PART="${DISK}p1"
else
    PART="${DISK}1"
fi

# 2. Membuat tabel partisi GPT baru dan membuat partisi EFI System Partition (ESP)
echo "[*] Membuat tabel partisi GPT dan partisi ESP pada $DISK..."
dd if=/dev/zero of="$DISK" bs=512 count=2048 conv=notrunc  # Bersihkan MBR/GPT lama
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 100%
parted -s "$DISK" set 1 esp on

# Menunggu partisi dikenali oleh kernel
udevadm settle || sleep 2

# 3. Memformat partisi sebagai FAT32
echo "[*] Memformat partisi $PART sebagai FAT32 (vfat)..."
mkfs.vfat -F32 "$PART"

# 4. Melakukan mounting
MNT_DIR="/tmp/mnt_target"
ISO_MNT="/tmp/mnt_iso"
mkdir -p "$MNT_DIR" "$ISO_MNT"

echo "[*] Melakukan mounting partisi dan ISO..."
mount "$PART" "$MNT_DIR"
mount -o loop,ro "$ISO_FILE" "$ISO_MNT"

# 5. Menyalin berkas boot Alpine
echo "[*] Menyalin berkas sistem Alpine Linux..."
mkdir -p "$MNT_DIR/boot"
cp "$ISO_MNT/boot/vmlinuz-virt" "$MNT_DIR/boot/"
cp "$ISO_MNT/boot/initramfs-virt" "$MNT_DIR/boot/"
cp "$ISO_MNT/boot/modloop-virt" "$MNT_DIR/boot/"
cp "$ISO_MNT/localhost.apkovl.tar.gz" "$MNT_DIR/"

# Salin folder apks (lokal repository) jika ada
if [ -d "$ISO_MNT/apks" ]; then
    cp -R "$ISO_MNT/apks" "$MNT_DIR/"
fi

# 6. Mendapatkan UUID partisi
PART_UUID=$(blkid -s UUID -o value "$PART")
echo "✔ UUID partisi terdeteksi: $PART_UUID"

# 7. Memasang GRUB bootloader untuk UEFI
echo "[*] Menginstal GRUB bootloader (UEFI mode)..."
grub-install --target=x86_64-efi --efi-directory="$MNT_DIR" --boot-directory="$MNT_DIR/boot" --removable

# 8. Membuat konfigurasi GRUB
echo "[*] Membuat konfigurasi grub.cfg..."
cat <<EOF > "$MNT_DIR/boot/grub/grub.cfg"
set default=0
set timeout=2

# Redirect console ke output serial dan monitor (sangat berguna untuk server VPS/dedicated)
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_output console serial
terminal_input console serial

menuentry "Alpine Linux RAM-only VPN" {
    # Cari partisi berdasarkan UUID
    search --no-floppy --fs-uuid --set=root $PART_UUID
    
    # Boot kernel dengan parameter RAM-only (diskless)
    # console=tty0 dan console=ttyS0 untuk output IPMI Serial Console
    linux /boot/vmlinuz-virt alpine_dev=UUID=$PART_UUID apkovl=UUID=$PART_UUID:/localhost.apkovl.tar.gz modloop=UUID=$PART_UUID:/boot/modloop-virt console=tty0 console=ttyS0,115200
    
    # Muat initramfs ke RAM
    initrd /boot/initramfs-virt
}
EOF

# 9. Clean up
echo "[*] Membersihkan dan melakukan unmount..."
umount "$MNT_DIR"
umount "$ISO_MNT"
rm -rf "$MNT_DIR" "$ISO_MNT"

echo "=================================================="
echo "✔ INSTALASI BERHASIL!"
echo "Sistem VPN RAM-only telah terpasang pada $DISK."
echo "Sekarang Anda dapat merestart server dari SystemRescue."
echo "Begitu reboot, sistem akan langsung memuat Alpine ke RAM."
echo "=================================================="
