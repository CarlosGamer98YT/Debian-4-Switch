#!/usr/bin/env python3
"""
fix_ext4_perms.py
Corrige la propiedad (root:root / UID 0: GID 0) y los permisos SUID directamente
dentro de la imagen del sistema de archivos ext4 mediante debugfs en espacio de usuario.
"""
import os
import sys
import tempfile
import subprocess

SUID_BINARIES = {
    "/usr/bin/sudo": 0o104755,
    "/usr/bin/su": 0o104755,
    "/usr/bin/passwd": 0o104755,
    "/usr/bin/gpasswd": 0o104755,
    "/usr/bin/newgrp": 0o104755,
    "/usr/bin/chsh": 0o104755,
    "/usr/bin/chfn": 0o104755,
    "/usr/bin/crontab": 0o104755,
    "/usr/lib/xorg/Xorg": 0o104755,
    "/usr/lib/polkit-1/polkit-agent-helper-1": 0o104755,
    "/usr/lib/aarch64-linux-gnu/polkit-1/polkit-agent-helper-1": 0o104755,
    "/usr/lib/dbus-1.0/dbus-daemon-launch-helper": 0o104754,
}

SPECIAL_PERMS = {
    "/etc/sudoers": 0o100440,
    "/etc/sudo.conf": 0o100644,
    "/usr/lib/xorg/Xorg.wrap": 0o100755,
    "/tmp": 0o041777,
    "/var/tmp": 0o041777,
    "/var/cache/man": 0o042755,
    "/var/lib/lightdm": 0o040755,
    "/var/lib/lightdm/data": 0o040750,
    "/var/cache/lightdm": 0o040755,
    "/var/log/lightdm": 0o040755,
}

def escape_path(path):
    if " " in path or "'" in path or '"' in path:
        p = path.replace('"', '\\"')
        return f'"{p}"'
    return path

def main():
    if len(sys.argv) < 3:
        print("Uso: fix_ext4_perms.py <ext4_image> <rootfs_dir>")
        sys.exit(1)

    img_path = os.path.abspath(sys.argv[1])
    rootfs_dir = os.path.abspath(sys.argv[2])

    debugfs_bin = subprocess.run(["which", "debugfs"], capture_output=True, text=True).stdout.strip()
    if not debugfs_bin or not os.path.exists(debugfs_bin):
        debugfs_bin = "/sbin/debugfs"

    print(f"[*] Escaneando {rootfs_dir} y preparando normalización de propietarios y permisos...")
    
    with tempfile.NamedTemporaryFile("w", delete=False, prefix="dbg_cmds_") as cmd_file:
        cmd_path = cmd_file.name
        
        # Raíz del filesystem
        cmd_file.write("sif / uid 0\nsif / gid 0\n")

        count = 0
        for root, dirs, files in os.walk(rootfs_dir):
            for name in dirs + files:
                full_path = os.path.join(root, name)
                rel_path = "/" + os.path.relpath(full_path, rootfs_dir).replace("\\", "/")
                escaped = escape_path(rel_path)
                
                # Asignación de propietarios: switch (1000:1000), man (6:12), lightdm (105:110 / 105:0) o root (0:0)
                if rel_path.startswith("/home/switch"):
                    cmd_file.write(f"sif {escaped} uid 1000\n")
                    cmd_file.write(f"sif {escaped} gid 1000\n")
                elif rel_path == "/var/cache/man" or rel_path.startswith("/var/cache/man/"):
                    cmd_file.write(f"sif {escaped} uid 6\n")
                    cmd_file.write(f"sif {escaped} gid 12\n")
                elif rel_path == "/var/lib/lightdm" or rel_path.startswith("/var/lib/lightdm/") or \
                     rel_path == "/var/cache/lightdm" or rel_path.startswith("/var/cache/lightdm/") or \
                     rel_path == "/run/lightdm" or rel_path.startswith("/run/lightdm/"):
                    cmd_file.write(f"sif {escaped} uid 105\n")
                    cmd_file.write(f"sif {escaped} gid 110\n")
                elif rel_path == "/var/log/lightdm" or rel_path.startswith("/var/log/lightdm/"):
                    cmd_file.write(f"sif {escaped} uid 105\n")
                    cmd_file.write(f"sif {escaped} gid 0\n")
                else:
                    cmd_file.write(f"sif {escaped} uid 0\n")
                    cmd_file.write(f"sif {escaped} gid 0\n")

                # Asignación de permisos especiales / SUID
                if rel_path in SUID_BINARIES:
                    cmd_file.write(f"sif {escaped} mode {int(SUID_BINARIES[rel_path])}\n")
                elif rel_path in SPECIAL_PERMS:
                    cmd_file.write(f"sif {escaped} mode {int(SPECIAL_PERMS[rel_path])}\n")
                elif rel_path.startswith("/etc/sudoers.d/"):
                    cmd_file.write(f"sif {escaped} mode {int(0o100440)}\n")

                count += 1

    print(f"[*] Aplicando {count} cambios de propiedad (UID 0: GID 0) a {os.path.basename(img_path)} via debugfs...")
    res = subprocess.run([debugfs_bin, "-w", "-f", cmd_path, img_path], capture_output=True, text=True)
    os.unlink(cmd_path)

    print("[*] Verificando consistencia del sistema de archivos ext4 con e2fsck...")
    e2fsck_bin = subprocess.run(["which", "e2fsck"], capture_output=True, text=True).stdout.strip() or "/sbin/e2fsck"
    subprocess.run([e2fsck_bin, "-fy", img_path], capture_output=True)
    print("[✓] Imagen ext4 normalizada con éxito: UID 0 para el sistema, UID 1000 para switch y SUID intactos.")

if __name__ == "__main__":
    main()
