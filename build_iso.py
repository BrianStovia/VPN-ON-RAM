import os
import urllib.request
import tarfile
import subprocess

ALPINE_VERSION = "3.20.1"
ARCH = "x86_64"
ORIGINAL_ISO = f"alpine-virt-{ALPINE_VERSION}-{ARCH}.iso"
ISO_URL = f"https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/{ARCH}/{ORIGINAL_ISO}"
CUSTOM_ISO = "alpine-vpn.iso"
APKOVL_TAR = "localhost.apkovl.tar.gz"


XORRISO_EXE = "xorriso.exe"
CYGWIN_DLL = "cygwin1.dll"
ICONV_DLL = "cygiconv-2.dll"

RAW_BASE = "https://raw.githubusercontent.com/PeyTy/xorriso-exe-for-windows/master"

def download_file(url, dest):
    print(f"[*] Downloading {url} -> {dest}...")
    # Setup standard User-Agent header to avoid block by GitHub
    req = urllib.request.Request(
        url, 
        headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
    )
    with urllib.request.urlopen(req) as response, open(dest, 'wb') as out_file:
        out_file.write(response.read())
    print(f"[OK] Downloaded {dest}.")

def build_apkovl_tar():
    print("[*] Building apkovl tarball with symlinks...")
    apkovl_dir = "./apkovl"
    
    with tarfile.open(APKOVL_TAR, "w:gz") as tar:
        # Add files from apkovl
        for root, dirs, files in os.walk(apkovl_dir):
            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, apkovl_dir)
                # Ensure forward slashes in tar archive paths
                tar_path = rel_path.replace("\\", "/")
                
                # Create TarInfo and set permissions
                tarinfo = tar.gettarinfo(full_path, tar_path)
                tarinfo.uid = 0
                tarinfo.gid = 0
                tarinfo.uname = "root"
                tarinfo.gname = "root"
                
                # Set permissions (specifically executable for vpn-init.start)
                if tar_path.endswith("vpn-init.start"):
                    tarinfo.mode = 0o755
                else:
                    tarinfo.mode = 0o644
                    
                with open(full_path, "rb") as f:
                    tar.addfile(tarinfo, f)
                    
        # Add symlinks for OpenRC
        symlinks = [
            ("etc/runlevels/default/local", "../../init.d/local"),
            ("etc/runlevels/default/sshd", "../../init.d/sshd")
        ]
        
        for name, target in symlinks:
            tarinfo = tarfile.TarInfo(name=name)
            tarinfo.type = tarfile.SYMTYPE
            tarinfo.linkname = target
            tarinfo.uid = 0
            tarinfo.gid = 0
            tarinfo.uname = "root"
            tarinfo.gname = "root"
            tar.addfile(tarinfo)
            
    print(f"[OK] Created {APKOVL_TAR}.")

def main():
    print("==================================================")
    print("      Building Alpine Linux VPN ISO (Windows)     ")
    print("==================================================")

    # 1. Download Alpine ISO if not exists
    if not os.path.exists(ORIGINAL_ISO):
        download_file(ISO_URL, ORIGINAL_ISO)
    else:
        print(f"[OK] Original Alpine ISO found: {ORIGINAL_ISO}")

    # 2. Download xorriso and dll dependencies if not exist
    deps = [
        (f"{RAW_BASE}/{XORRISO_EXE}", XORRISO_EXE),
        (f"{RAW_BASE}/{CYGWIN_DLL}", CYGWIN_DLL),
        (f"{RAW_BASE}/{ICONV_DLL}", ICONV_DLL),
    ]
    
    for url, dest in deps:
        if not os.path.exists(dest):
            download_file(url, dest)
        else:
            print(f"[OK] Dependency found: {dest}")

    # 3. Build Apkovl Tarball
    build_apkovl_tar()

    # 4. Run xorriso to build the new ISO
    print("[*] Running xorriso to inject apkovl...")
    if os.path.exists(CUSTOM_ISO):
        os.remove(CUSTOM_ISO)
        
    xorriso_path = os.path.abspath(XORRISO_EXE)
    cmd = [
        xorriso_path,
        "-indev", ORIGINAL_ISO,
        "-outdev", CUSTOM_ISO,
        "-map", APKOVL_TAR, f"/{APKOVL_TAR}",
        "-boot_image", "any", "replay"
    ]
    
    subprocess.run(cmd, check=True)
    
    print("\n==================================================")
    print(f"[OK] ISO Remastering Selesai!")
    print(f"File ISO Baru: {CUSTOM_ISO}")
    print("==================================================")
    
    # Clean up temporary tools and tarball
    print("[*] Cleaning up temporary files...")
    for file in [XORRISO_EXE, CYGWIN_DLL, ICONV_DLL, APKOVL_TAR]:
        if os.path.exists(file):
            try:
                os.remove(file)
            except Exception as e:
                print(f"Warning: Gagal menghapus {file}: {e}")
    print("[OK] Clean up complete.")

if __name__ == "__main__":
    main()
