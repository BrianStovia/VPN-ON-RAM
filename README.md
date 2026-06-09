# 1. Unduh ulang skrip penginstal yang sudah diperbaiki
curl -L "https://raw.githubusercontent.com/BrianStovia/VPN-ON-RAM/main/install.sh" -o install.sh

# 2. Jalankan ulang penginstalan (ganti /dev/sda sesuai disk target Anda)
chmod +x install.sh
./install.sh /dev/sda

# 3. Ketik 'y' untuk melanjutkan, setelah sukses jalankan restart
reboot
