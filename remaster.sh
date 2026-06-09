#!/bin/bash
set -e

# Konfigurasi versi Alpine
ALPINE_VERSION="3.20.1"
ARCH="x86_64"
ORIGINAL_ISO="alpine-virt-${ALPINE_VERSION}-${ARCH}.iso"
ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/${ARCH}/${ORIGINAL_ISO}"
CUSTOM_ISO="alpine-vpn.iso"

APKOVL_DIR="./apkovl"
STAGING_DIR="./build_tmp"
APKOVL_TAR="localhost.apkovl.tar.gz"

echo "=================================================="
echo "      Alpine Linux VPN ISO Remastering Script     "
echo "=================================================="

# 1. Cek dependensi
echo "[*] Memeriksa dependensi..."
for cmd in tar gzip xorriso; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: perintah '$cmd' tidak ditemukan. Silakan pasang terlebih dahulu."
        exit 1
    fi
done
echo "✔ Semua dependensi terpasang."

# 2. Cek direktori apkovl
if [ ! -d "$APKOVL_DIR" ]; then
    echo "Error: Direktori '$APKOVL_DIR' tidak ditemukan!"
    exit 1
fi

# 3. Download ISO asli jika belum ada
if [ ! -f "$ORIGINAL_ISO" ]; then
    echo "[*] ISO Alpine asli tidak ditemukan. Mencoba mengunduh..."
    if command -v curl &> /dev/null; then
        curl -L -o "$ORIGINAL_ISO" "$ISO_URL"
    elif command -v wget &> /dev/null; then
        wget -O "$ORIGINAL_ISO" "$ISO_URL"
    else
        echo "Error: 'curl' atau 'wget' tidak ditemukan. Silakan unduh ISO secara manual di:"
        echo "  $ISO_URL"
        echo "dan letakkan di direktori ini dengan nama '$ORIGINAL_ISO'."
        exit 1
    fi
    echo "✔ Selesai mengunduh ISO."
else
    echo "✔ ISO Alpine asli ditemukan: $ORIGINAL_ISO"
fi

# 4. Membuat Staging Area untuk APKOVL
echo "[*] Menyiapkan staging area untuk .apkovl..."
rm -rf "$STAGING_DIR" "$APKOVL_TAR"
mkdir -p "$STAGING_DIR"

# Menyalin file konfigurasi
cp -R "$APKOVL_DIR"/* "$STAGING_DIR"/

# Memastikan script inisialisasi executable
chmod +x "$STAGING_DIR"/etc/local.d/vpn-init.start

# Membuat symlink OpenRC untuk boot runlevel
# Ini dilakukan di sini untuk menghindari masalah penulisan symlink di host OS Windows
echo "[*] Membuat OpenRC symlink..."
mkdir -p "$STAGING_DIR"/etc/runlevels/default
ln -sf ../../init.d/local "$STAGING_DIR"/etc/runlevels/default/local
ln -sf ../../init.d/sshd "$STAGING_DIR"/etc/runlevels/default/sshd

# 5. Membuat berkas .apkovl.tar.gz
echo "[*] Mengompres konfigurasi menjadi $APKOVL_TAR..."
tar -czf "$APKOVL_TAR" -C "$STAGING_DIR" .
rm -rf "$STAGING_DIR"
echo "✔ Berhasil membuat $APKOVL_TAR."

# 6. Menggunakan xorriso untuk menyuntikkan .apkovl ke ISO
echo "[*] Melakukan remastering ISO menggunakan xorriso..."
if [ -f "$CUSTOM_ISO" ]; then
    rm "$CUSTOM_ISO"
fi

xorriso -indev "$ORIGINAL_ISO" \
        -outdev "$CUSTOM_ISO" \
        -map "$APKOVL_TAR" "/$APKOVL_TAR" \
        -boot_image any replay

echo "=================================================="
echo "✔ Remastering Selesai!"
echo "ISO baru berhasil dibuat: $CUSTOM_ISO"
echo "Anda dapat membakar ISO ini ke USB flashdisk atau mengujinya di VM."
echo "=================================================="
