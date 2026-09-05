#!/usr/bin/env python3
import os, sys, re, urllib.request, subprocess
from concurrent.futures import ThreadPoolExecutor

CWD = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(CWD)
DOWNLOADS_DIR = os.path.join(PROJECT_DIR, "downloads", "gui-debs")
ROOTFS_DIR = os.path.join(PROJECT_DIR, "build_output", "rootfs")
PKG_INDEX = os.path.join(DOWNLOADS_DIR, "Packages_trixie_arm64")
DEBIAN_MIRROR = "http://deb.debian.org/debian/"

os.makedirs(DOWNLOADS_DIR, exist_ok=True)

if not os.path.exists(PKG_INDEX):
    print("[*] Descargando índice de paquetes Debian 13 ARM64...")
    urllib.request.urlretrieve(f"{DEBIAN_MIRROR}dists/trixie/main/binary-arm64/Packages.xz", f"{PKG_INDEX}.xz")
    subprocess.run(["xz", "-d", "-f", f"{PKG_INDEX}.xz"], check=True)

print("[*] Parseando índice de paquetes...")
packages = {}
with open(PKG_INDEX, "r", encoding="utf-8", errors="ignore") as f:
    cur = {}
    for line in f:
        line = line.rstrip()
        if not line:
            if "Package" in cur:
                packages[cur["Package"]] = cur
            cur = {}
            continue
        if ": " in line:
            k, v = line.split(": ", 1)
            cur[k] = v
    if "Package" in cur:
        packages[cur["Package"]] = cur

print(f"[✓] {len(packages)} paquetes disponibles en Debian 13 (Trixie).")

targets = [
    "xfce4", "xfce4-session", "xfwm4", "xfdesktop4", "xfce4-panel", "xfce4-settings",
    "xfce4-terminal", "thunar", "lightdm", "lightdm-gtk-greeter", "accountsservice", "xserver-xorg-core",
    "xserver-xorg-legacy", "xserver-xorg-video-fbdev", "xserver-xorg-video-modesetting", "xserver-xorg-input-libinput", "xinit",
    "x11-xserver-utils", "x11-xkb-utils", "xkb-data", "xauth", "x11-utils", "xinput", "xrandr", "onboard",
    "firefox-esr", "fastfetch", "libgl1-mesa-dri", "mesa-utils", "desktop-base", "adwaita-icon-theme", "adwaita-icon-theme-legacy", "hicolor-icon-theme",
    "alsa-utils", "alsa-ucm-conf", "alsa-topology-conf", "pulseaudio", "pulseaudio-utils", "pulseaudio-module-bluetooth", "pavucontrol",
    "xfce4-pulseaudio-plugin", "xfce4-power-manager", "xfce4-power-manager-plugins",
    "xfce4-notifyd", "xfce4-screenshooter", "xfce4-taskmanager", "xfce4-indicator-plugin", "xfce4-genmon-plugin", "ayatana-indicator-application", "xapp-sn-watcher",
    "network-manager", "network-manager-gnome", "gir1.2-nm-1.0", "gir1.2-nma-1.0", "wpasupplicant", "wireless-tools", "rfkill", "wireless-regdb", "iw",
    "systemd-timesyncd", "blueman", "bluez", "lxpolkit", "gvfs", "gvfs-backends", "xdotool",
    "gir1.2-notify-0.7", "gir1.2-ayatanaappindicator3-0.1", "gir1.2-freedesktop", "libnotify-bin", "libnotify4",
    "sudo", "systemd", "systemd-sysv", "dbus", "dbus-x11", "dbus-user-session", "libpam-systemd",
    "policykit-1", "libgdk-pixbuf2.0-bin", "librsvg2-common", "shared-mime-info",
    "libpng16-16t64", "libjpeg62-turbo", "libtiff6",
    "cron", "cron-daemon-common", "locales", "libc-l10n", "man-db"
]

to_install = {}
queue = list(targets)
visited = set()

while queue:
    pkg = queue.pop(0)
    if pkg in visited:
        continue
    visited.add(pkg)
    if pkg not in packages:
        continue
    info = packages[pkg]
    to_install[pkg] = info
    deps = info.get("Depends", "") + ", " + info.get("Pre-Depends", "")
    for dep_clause in deps.split(","):
        dep_clause = dep_clause.strip()
        if not dep_clause:
            continue
        alt = dep_clause.split("|")[0].strip()
        dep_name = re.sub(r"\(.*?\)", "", alt).strip()
        if dep_name and dep_name in packages and dep_name not in visited:
            queue.append(dep_name)

print(f"[*] Total de paquetes a instalar para entorno gráfico: {len(to_install)}")

def download_pkg(item):
    name, info = item
    fn = info["Filename"]
    deb_name = os.path.basename(fn)
    dest = os.path.join(DOWNLOADS_DIR, deb_name)
    if os.path.exists(dest) and os.path.getsize(dest) == int(info.get("Size", -1)):
        return deb_name, dest
    url = DEBIAN_MIRROR + fn
    try:
        urllib.request.urlretrieve(url, dest)
    except Exception as e:
        print(f"Error descargando {name}: {e}")
        return None
    return deb_name, dest

print("[*] Descargando paquetes .deb con 16 hilos paralelos...")
with ThreadPoolExecutor(max_workers=16) as ex:
    results = list(ex.map(download_pkg, to_install.items()))

downloaded = [r[1] for r in results if r is not None]
print(f"[✓] {len(downloaded)} paquetes .deb listos para instalación.")

print("[*] Extrayendo paquetes en el RootFS...")
for deb in downloaded:
    cmd = (
        f"ar p '{deb}' data.tar.xz 2>/dev/null | tar -xf - -C '{ROOTFS_DIR}' --keep-directory-symlink --overwrite 2>/dev/null || "
        f"ar p '{deb}' data.tar.gz 2>/dev/null | tar -xf - -C '{ROOTFS_DIR}' --keep-directory-symlink --overwrite 2>/dev/null || "
        f"ar p '{deb}' data.tar.zst 2>/dev/null | tar -xf - -C '{ROOTFS_DIR}' --keep-directory-symlink --overwrite 2>/dev/null || "
        f"dpkg-deb -x '{deb}' '{ROOTFS_DIR}' 2>/dev/null || true"
    )
    subprocess.run(cmd, shell=True)

print("[✓] Extracción de paquetes completada.")
