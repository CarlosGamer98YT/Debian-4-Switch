#!/bin/bash
set -e

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}"
if [ "$(basename "${ROOT_DIR}")" = "tools" ]; then
    ROOT_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
fi
ROOTFS_DIR="${ROOT_DIR}/build_output/rootfs"
BUILD_OUTPUT="${ROOT_DIR}/build_output"
INSTALL_STAGE="${BUILD_OUTPUT}/switchroot_installer_stage"
OUTPUT_DIR="${BUILD_OUTPUT}/switchroot_install"
IMG_FILE="${BUILD_OUTPUT}/switch_debian13_rootfs.img"

echo "========================================================"
echo "   Switchroot / Hekate L4T Installer Package Creator"
echo "========================================================"

if [ ! -d "${ROOTFS_DIR}" ]; then
    echo "[!] Error: No se encontró el directorio rootfs en ${ROOTFS_DIR}"
    exit 1
fi

MKE2FS=$(which mke2fs || echo "/sbin/mke2fs")
if [ ! -x "$MKE2FS" ]; then
    MKE2FS="/usr/sbin/mke2fs"
fi

if [ ! -x "$MKE2FS" ]; then
    echo "[!] Error: mke2fs no está instalado o no se encuentra en PATH."
    exit 1
fi

echo "[*] Asegurando propiedad root:root (UID 0: GID 0) y permisos de seguridad en RootFS..."
if [ "$(id -u)" -eq 0 ]; then
    chown -R 0:0 "${ROOTFS_DIR}" 2>/dev/null || true
    [ -d "${ROOTFS_DIR}/home/switch" ] && chown -R 1000:1000 "${ROOTFS_DIR}/home/switch" 2>/dev/null || true
    [ -d "${ROOTFS_DIR}/var/lib/lightdm" ] && chown -R 105:110 "${ROOTFS_DIR}/var/lib/lightdm" 2>/dev/null || true
    [ -d "${ROOTFS_DIR}/var/cache/lightdm" ] && chown -R 105:110 "${ROOTFS_DIR}/var/cache/lightdm" 2>/dev/null || true
    [ -d "${ROOTFS_DIR}/var/log/lightdm" ] && chown -R 105:0 "${ROOTFS_DIR}/var/log/lightdm" 2>/dev/null || true
    chmod 755 "${ROOTFS_DIR}/var/lib/lightdm" "${ROOTFS_DIR}/var/cache/lightdm" "${ROOTFS_DIR}/var/log/lightdm" 2>/dev/null || true
    [ -d "${ROOTFS_DIR}/var/lib/lightdm/data" ] && chmod 750 "${ROOTFS_DIR}/var/lib/lightdm/data" 2>/dev/null || true
    chown 0:0 "${ROOTFS_DIR}/etc/sudoers" "${ROOTFS_DIR}/etc/sudo.conf" 2>/dev/null || true
    chown -R 0:0 "${ROOTFS_DIR}/etc/sudoers.d" 2>/dev/null || true
    chmod 0440 "${ROOTFS_DIR}/etc/sudoers" 2>/dev/null || true
    chmod 0440 "${ROOTFS_DIR}/etc/sudoers.d"/* 2>/dev/null || true
    [ -f "${ROOTFS_DIR}/etc/sudo.conf" ] && chmod 0644 "${ROOTFS_DIR}/etc/sudo.conf" 2>/dev/null || true
    chmod 4755 "${ROOTFS_DIR}/usr/bin/sudo" "${ROOTFS_DIR}/usr/bin/su" 2>/dev/null || true
elif command -v sudo >/dev/null 2>&1; then
    sudo chown -R 0:0 "${ROOTFS_DIR}" 2>/dev/null || true
    [ -d "${ROOTFS_DIR}/home/switch" ] && sudo chown -R 1000:1000 "${ROOTFS_DIR}/home/switch" 2>/dev/null || true
    [ -d "${ROOTFS_DIR}/var/lib/lightdm" ] && sudo chown -R 105:110 "${ROOTFS_DIR}/var/lib/lightdm" 2>/dev/null || true
    [ -d "${ROOTFS_DIR}/var/cache/lightdm" ] && sudo chown -R 105:110 "${ROOTFS_DIR}/var/cache/lightdm" 2>/dev/null || true
    [ -d "${ROOTFS_DIR}/var/log/lightdm" ] && sudo chown -R 105:0 "${ROOTFS_DIR}/var/log/lightdm" 2>/dev/null || true
    sudo chmod 755 "${ROOTFS_DIR}/var/lib/lightdm" "${ROOTFS_DIR}/var/cache/lightdm" "${ROOTFS_DIR}/var/log/lightdm" 2>/dev/null || true
    [ -d "${ROOTFS_DIR}/var/lib/lightdm/data" ] && sudo chmod 750 "${ROOTFS_DIR}/var/lib/lightdm/data" 2>/dev/null || true
    sudo chown 0:0 "${ROOTFS_DIR}/etc/sudoers" "${ROOTFS_DIR}/etc/sudo.conf" 2>/dev/null || true
    sudo chown -R 0:0 "${ROOTFS_DIR}/etc/sudoers.d" 2>/dev/null || true
    sudo chmod 0440 "${ROOTFS_DIR}/etc/sudoers" 2>/dev/null || true
    sudo chmod 0440 "${ROOTFS_DIR}/etc/sudoers.d"/* 2>/dev/null || true
    [ -f "${ROOTFS_DIR}/etc/sudo.conf" ] && sudo chmod 0644 "${ROOTFS_DIR}/etc/sudo.conf" 2>/dev/null || true
    sudo chmod 4755 "${ROOTFS_DIR}/usr/bin/sudo" "${ROOTFS_DIR}/usr/bin/su" 2>/dev/null || true
fi

echo "[1/4] Creando imagen de sistema de archivos ext4 (5120 MiB)..."
rm -f "${IMG_FILE}"
mkdir -p "${OUTPUT_DIR}" "${INSTALL_STAGE}/switchroot/install"

# Crear imagen ext4 etiquetada SWR-DEB directamente a partir del rootfs
"$MKE2FS" -t ext4 -d "${ROOTFS_DIR}" -L "SWR-DEB" -b 4096 -O extents,uninit_bg,dir_index "${IMG_FILE}" 5120M

echo "[*] Normalizando propietarios (UID 0: GID 0) y permisos SUID en la imagen ext4..."
FIX_PERMS_PY="${ROOT_DIR}/tools/fix_ext4_perms.py"
[ ! -f "${FIX_PERMS_PY}" ] && FIX_PERMS_PY="${SCRIPT_DIR}/fix_ext4_perms.py"
python3 "${FIX_PERMS_PY}" "${IMG_FILE}" "${ROOTFS_DIR}"

echo "[2/4] Dividiendo imagen para Hekate Nyx (partes alineadas a 4 MiB)..."
# 4092 MiB = 4290772992 bytes (múltiplo estricto de 4 MiB, compatible con FAT32 y Hekate Nyx)
rm -f "${INSTALL_STAGE}/switchroot/install"/l4t.*
split -b 4092M -d -a 2 "${IMG_FILE}" "${INSTALL_STAGE}/switchroot/install/l4t."

rm -f "${IMG_FILE}"

echo "[3/4] Sincronizando bootloader y archivos de arranque para FAT32..."
if [ -d "${BUILD_OUTPUT}/boot_fat32" ]; then
    cp -rf "${BUILD_OUTPUT}/boot_fat32"/* "${INSTALL_STAGE}/"
fi

echo "[4/4] Empaquetando instalador final para tarjeta SD..."
DESKTOP_ENV="${DESKTOP_ENV:-xfce4}"
ZIP_OUT="${BUILD_OUTPUT}/switch-debian-13-trixie-${DESKTOP_ENV}-installer-hekate.zip"
rm -f "${ZIP_OUT}"
(cd "${INSTALL_STAGE}" && zip -r -q "${ZIP_OUT}" .)

echo "Generando checksums SHA256..."
(cd "${INSTALL_STAGE}/switchroot/install" && sha256sum l4t.* > SHA256SUMS.txt)
(cd "${BUILD_OUTPUT}" && sha256sum switch-debian-13-trixie-${DESKTOP_ENV}-* > SHA256SUMS.txt)

# Liberar 5.1 GB eliminando stage temporal (el zip ya contiene las partes)
rm -rf "${INSTALL_STAGE}"

echo "========================================================"
echo " [✓] Instalador Switchroot Hekate creado con éxito:"
echo "     -> ${ZIP_OUT}"
echo "========================================================"
