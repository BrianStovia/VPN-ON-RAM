#cloud-config
runcmd:
  # 1. Unduh berkas ISO kustom Anda dari Google Drive ke folder /root
  - curl -L "https://drive.google.com/uc?export=download&id=1Pgije7_oqYsPdeoHXM8BIn-_OUERxM68" -o /root/alpine-vpn.iso
  # 2. Unduh skrip injeksi GRUB dari repositori GitHub Anda
  - curl -L "https://raw.githubusercontent.com/BrianStovia/VPN-ON-RAM/main/cloud-init-deploy.sh" -o /root/cloud-init-deploy.sh
  # 3. Berikan izin eksekusi dan jalankan skrip injeksi
  - chmod +x /root/cloud-init-deploy.sh
  - /root/cloud-init-deploy.sh
