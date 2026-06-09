import os
import subprocess
import base64
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization

def generate_wg_keypair():
    private_key = x25519.X25519PrivateKey.generate()
    private_bytes = private_key.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption()
    )
    public_key = private_key.public_key()
    public_bytes = public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )
    
    private_b64 = base64.b64encode(private_bytes).decode('utf-8')
    public_b64 = base64.b64encode(public_bytes).decode('utf-8')
    return private_b64, public_b64

def main():
    print("=== Menyiapkan Kunci SSH dan WireGuard Siap Pakai ===")
    
    # 1. Generate SSH Keypair
    ssh_key_path = "./id_ed25519"
    if not os.path.exists(ssh_key_path):
        print("[*] Membuat SSH keypair baru (ED25519)...")
        subprocess.run(["ssh-keygen", "-t", "ed25519", "-N", "", "-f", ssh_key_path], check=True)
        print("[OK] SSH Keypair berhasil dibuat.")
    else:
        print("[OK] SSH Keypair sudah ada.")
        
    # Membaca SSH Public Key
    with open(ssh_key_path + ".pub", "r") as f:
        ssh_pub_key = f.read().strip()
        
    # Menulis ke authorized_keys
    auth_keys_dir = "./apkovl/root/.ssh"
    os.makedirs(auth_keys_dir, exist_ok=True)
    with open(os.path.join(auth_keys_dir, "authorized_keys"), "w") as f:
        f.write(ssh_pub_key + "\n")
    print("[OK] SSH Public Key berhasil dimasukkan ke apkovl/root/.ssh/authorized_keys.")
    
    # 2. Generate WireGuard Keys
    print("[*] Membuat kunci WireGuard Server dan Client...")
    server_priv, server_pub = generate_wg_keypair()
    client_priv, client_pub = generate_wg_keypair()
    
    # 3. Update wg0.conf
    wg_conf_path = "./apkovl/etc/wireguard/wg0.conf"
    if os.path.exists(wg_conf_path):
        print("[*] Mengonfigurasi apkovl/etc/wireguard/wg0.conf...")
        with open(wg_conf_path, "r") as f:
            content = f.read()
            
        # Ganti placeholder
        content = content.replace("<VPN_SERVER_PRIVATE_KEY>", server_priv)
        content = content.replace("#[Peer]", "[Peer]")
        content = content.replace("#PublicKey = <CLIENT_PUBLIC_KEY>", f"PublicKey = {client_pub}")
        content = content.replace("#AllowedIPs = 10.8.0.2/32", "AllowedIPs = 10.8.0.2/32")
        # Menghapus komentar penjelas yang di-uncomment
        content = content.replace("#PublicKey", "PublicKey")
        content = content.replace("#AllowedIPs", "AllowedIPs")
        
        with open(wg_conf_path, "w") as f:
            f.write(content)
        print("[OK] apkovl/etc/wireguard/wg0.conf berhasil diperbarui dengan kunci baru.")
    else:
        print("[ERROR] apkovl/etc/wireguard/wg0.conf tidak ditemukan.")
        
    # 4. Membuat client.conf
    client_conf_path = "./client.conf"
    print(f"[*] Membuat file konfigurasi client di {client_conf_path}...")
    client_content = f"""[Interface]
PrivateKey = {client_priv}
Address = 10.8.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = {server_pub}
# Ganti <SERVER_PUBLIC_IP> dengan IP publik atau domain dari server VPN Anda
Endpoint = <SERVER_PUBLIC_IP>:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"""
    with open(client_conf_path, "w") as f:
        f.write(client_content)
    print("[OK] client.conf berhasil dibuat.")
    
    print("\n=== Proses Selesai! ===")
    print("Berkas berikut telah dibuat dan dikonfigurasi:")
    print("  1. Private key SSH: ./id_ed25519 (Gunakan untuk login root ke server)")
    print("  2. Konfigurasi Client: ./client.conf (Gunakan pada aplikasi Wireguard Anda)")
    print("\nSekarang Anda dapat menjalankan skrip remaster.sh untuk membuat ISO.")


if __name__ == "__main__":
    main()
