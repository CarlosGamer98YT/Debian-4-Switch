#!/usr/bin/env bash
# ==============================================================================
# Script de Construcción: Debian GNU/Linux 13 (Trixie) ARM64 para Nintendo Switch
# Distribución: Debian 13 (Trixie)
# Target Hardware: Nintendo Switch (Erista V1, Mariko V2, Lite, OLED)
# ==============================================================================
set -euo pipefail

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${CWD}/build_output"
ROOTFS_DIR="${WORKDIR}/rootfs"
BOOT_DIR="${WORKDIR}/boot_fat32"
KERNEL_DIR="${CWD}/kernel/switch-l4t-kernel-4.9"
TOOLS_DIR="${CWD}/tools"
DOWNLOADS_DIR="${CWD}/downloads"

ARCH=arm64
export ARCH

echo "========================================================================"
echo "  CONSTRUCCIÓN DE DEBIAN 13 (TRIXIE) ARM64 PARA NINTENDO SWITCH"
echo "========================================================================"

# ------------------------------------------------------------------------------
# PASO 0: Verificación de Herramientas de Compilación
# ------------------------------------------------------------------------------
echo "[*] Paso 0: Verificando herramientas de compilación cruzada..."
mkdir -p "${TOOLS_DIR}/cross-bin" "${WORKDIR}" "${DOWNLOADS_DIR}"

if command -v aarch64-linux-gnu-gcc &> /dev/null; then
    CROSS_COMPILE="aarch64-linux-gnu-"
    export CROSS_COMPILE
    echo "[✓] Toolchain cruzada del sistema detectada: $(aarch64-linux-gnu-gcc --version | head -n 1)"
else
    echo "[!] Toolchain cruzada no instalada en sistema. Configurando toolchain local..."
    cd "${TOOLS_DIR}"
    apt-get download gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
      gcc-14-aarch64-linux-gnu cpp-14-aarch64-linux-gnu \
      libc6-dev-arm64-cross linux-libc-dev-arm64-cross u-boot-tools || true
    for f in *.deb; do [ -f "$f" ] && dpkg -x "$f" ./; done
    cd "${CWD}"

    cat << 'EOF' > "${TOOLS_DIR}/cross-bin/aarch64-linux-gnu-gcc"
#!/bin/bash
REAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LD_LIBRARY_PATH="${REAL_DIR}/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
exec "${REAL_DIR}/usr/bin/aarch64-linux-gnu-gcc" -B"${REAL_DIR}/usr/libexec/gcc-cross/aarch64-linux-gnu/14/" -B"${REAL_DIR}/usr/aarch64-linux-gnu/bin/" "$@"
EOF
    chmod +x "${TOOLS_DIR}/cross-bin/aarch64-linux-gnu-gcc"

    for tool in ld as ar ranlib nm strip objcopy objdump; do
    cat << EOF > "${TOOLS_DIR}/cross-bin/aarch64-linux-gnu-${tool}"
#!/bin/bash
REAL_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
export LD_LIBRARY_PATH="\${REAL_DIR}/usr/lib/x86_64-linux-gnu:\${LD_LIBRARY_PATH:-}"
exec "\${REAL_DIR}/usr/bin/aarch64-linux-gnu-${tool}" "\$@"
EOF
    chmod +x "${TOOLS_DIR}/cross-bin/aarch64-linux-gnu-${tool}"
    done
    export PATH="${TOOLS_DIR}/cross-bin:${TOOLS_DIR}/usr/bin:${PATH}"
    export LD_LIBRARY_PATH="${TOOLS_DIR}/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
    CROSS_COMPILE="${TOOLS_DIR}/cross-bin/aarch64-linux-gnu-"
    export CROSS_COMPILE
    echo "[✓] Toolchain cruzada local lista: $(aarch64-linux-gnu-gcc --version | head -n 1)"
fi

# ------------------------------------------------------------------------------
# PASO 1: Descarga y Extracción de Debian 13 (Trixie) ARM64 RootFS
# ------------------------------------------------------------------------------
echo "[*] Paso 1: Preparando Debian 13 (Trixie) ARM64 RootFS..."
RAW_IMAGE="${DOWNLOADS_DIR}/debian-13-nocloud-arm64-daily.tar.xz"
ROOTFS_EXT4="${DOWNLOADS_DIR}/rootfs.ext4"

if [ ! -f "${ROOTFS_EXT4}" ]; then
    echo "[*] Descargando imagen oficial base Debian 13 (Trixie) ARM64..."
    curl -L -o "${RAW_IMAGE}" "https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-nocloud-arm64-daily.tar.xz"
    tar -xf "${RAW_IMAGE}" -C "${DOWNLOADS_DIR}/"
    7z x -so "${DOWNLOADS_DIR}/disk.raw" 0.img > "${ROOTFS_EXT4}"
fi

echo "[*] Extrayendo RootFS preservando enlaces simbólicos..."
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"
/sbin/debugfs -R "rdump / ${ROOTFS_DIR}" "${ROOTFS_EXT4}" > /dev/null 2>&1 || true

echo "  -> Liberando espacio de imágenes crudas temporales de Debian..."
rm -f "${RAW_IMAGE}" "${ROOTFS_EXT4}" "${DOWNLOADS_DIR}/disk.raw" 2>/dev/null || true

# ------------------------------------------------------------------------------
# PASO 2: Compilación de Kernel Linux 4.9 L4T y Device Trees
# ------------------------------------------------------------------------------
echo "[*] Paso 2: Compilando Kernel Linux Switch L4T y Device Trees..."
mkdir -p "${CWD}/kernel"
if [ ! -d "${KERNEL_DIR}" ]; then
    echo "  -> Clonando switch-l4t-kernel-4.9..."
    git clone --depth 1 -b "linux-dev" https://github.com/theofficialgman/switch-l4t-kernel-4.9.git "${KERNEL_DIR}"
fi
if [ ! -d "${CWD}/kernel/nvidia" ]; then
    echo "  -> Clonando subsistemas y drivers Nvidia Tegra..."
    git clone --depth 1 -b "linux-dev" https://github.com/theofficialgman/switch-l4t-kernel-nvidia.git "${CWD}/kernel/nvidia"
    git clone --depth 1 -b "linux-dev" https://github.com/theofficialgman/switch-l4t-platform-t210-nx.git "${CWD}/kernel/hardware/nvidia/platform/t210/nx"
    git clone --depth 1 -b "linux-3.4.0-r32.5" https://gitlab.com/switchroot/kernel/l4t-kernel-nvgpu "${CWD}/kernel/nvgpu"
    git clone --depth 1 -b "l4t/l4t-r32.5" https://gitlab.com/switchroot/kernel/l4t-soc-t210 "${CWD}/kernel/hardware/nvidia/soc/t210"
    git clone --depth 1 -b "l4t/l4t-r32.5" https://gitlab.com/switchroot/kernel/l4t-soc-tegra "${CWD}/kernel/hardware/nvidia/soc/tegra/"
    git clone --depth 1 -b "l4t/l4t-r32.5" https://gitlab.com/switchroot/kernel/l4t-platform-tegra-common "${CWD}/kernel/hardware/nvidia/platform/tegra/common/"
    git clone --depth 1 -b "l4t/l4t-r32.5" https://gitlab.com/switchroot/kernel/l4t-platform-t210-common "${CWD}/kernel/hardware/nvidia/platform/t210/common/"
    
    if [ -f "${CWD}/patches/kernel/0001-Bluetooth-backport-BlueZ-5.8x-mgmt-opcodes-and-fix-c.patch" ]; then
        echo "  -> Aplicando parche Bluetooth para BlueZ 5.8x..."
        git -C "${KERNEL_DIR}" apply "${CWD}/patches/kernel/0001-Bluetooth-backport-BlueZ-5.8x-mgmt-opcodes-and-fix-c.patch" || true
    fi
fi

cd "${KERNEL_DIR}"
export KCFLAGS="-w"

if [ ! -f ".config" ]; then
    make tegra_linux_defconfig
fi

make -j"$(nproc)" Image.gz modules dtbs tegra-dtstree="../hardware/nvidia"

echo "[*] Instalando módulos del kernel en RootFS..."
make modules_install INSTALL_MOD_PATH="${ROOTFS_DIR}"
echo "  -> Liberando espacio de objetos compilados intermedios del kernel..."
find "${KERNEL_DIR}" -name "*.o" -delete 2>/dev/null || true
rm -f "${KERNEL_DIR}/vmlinux" 2>/dev/null || true
cd "${CWD}"

# ------------------------------------------------------------------------------
# PASO 3: Inyección de Paquetes de Switch y Entorno Gráfico XFCE4
# ------------------------------------------------------------------------------
echo "[*] Paso 3: Instalando controladores de Switch y entorno gráfico XFCE4..."
DEBS_DIR="${DOWNLOADS_DIR}/switch-debs"
mkdir -p "${DEBS_DIR}"
BASE_URL="https://theofficialgman.github.io/l4t-debs"

if [ ! -f "${DEBS_DIR}/Packages" ]; then
  echo "  -> Descargando índice de paquetes L4T..."
  curl -sL "${BASE_URL}/dists/l4t/jammy/binary-arm64/Packages.gz" | gzip -dc > "${DEBS_DIR}/Packages"
fi

for pkg in joycond nvidia-l4t-3d-core nvidia-l4t-configs nvidia-l4t-core nvidia-l4t-firmware nvidia-l4t-init nvidia-l4t-multimedia nvidia-l4t-multimedia-utils nvidia-l4t-x11 switch-alsa-ucm2 switch-bsp switch-dock-handler switch-joystick-mouse switch-touch-rules switch-l4t-configs; do
  if ! ls "${DEBS_DIR}/${pkg}"*.deb 1> /dev/null 2>&1; then
    url=$(awk -v p="$pkg" '$1=="Package:" && $2==p {found=1} found && $1=="Filename:" {print $2; exit}' "${DEBS_DIR}/Packages" || true)
    if [ -n "$url" ]; then
      echo "  -> Descargando $pkg..."
      curl -sL -o "${DEBS_DIR}/${pkg}.deb" "${BASE_URL}/${url}"
    fi
  fi
done

for deb in "${DEBS_DIR}"/*.deb; do
  if [ -f "$deb" ]; then
    echo "  -> Extrayendo $(basename "$deb") en RootFS..."
    dpkg-deb -x "$deb" "${ROOTFS_DIR}"
  fi
done
rm -f "${DEBS_DIR}"/*.deb "${DEBS_DIR}/Packages" 2>/dev/null || true

# Inyectar paquetes personalizados adaptados por el usuario
for deb in "${WORKDIR}"/*.deb; do
  if [ -f "$deb" ]; then
    echo "  -> Extrayendo paquete adaptado por usuario: $(basename "$deb")..."
    dpkg-deb -x "$deb" "${ROOTFS_DIR}"
  fi
done

echo "[*] Instalando entorno gráfico XFCE4, LightDM y utilidades táctiles..."
python3 "${TOOLS_DIR}/install_gui.py"

# ------------------------------------------------------------------------------
# PASO 4: Configuración del Sistema Debian 13 (Trixie) y UsrMerge
# ------------------------------------------------------------------------------
echo "[*] Paso 4: Consolidando UsrMerge y configurando entorno gráfico Debian 13..."

# Asegurar integridad de UsrMerge (Debian 13 requiere lib -> usr/lib)
if [ -d "${ROOTFS_DIR}/lib" ] && [ ! -L "${ROOTFS_DIR}/lib" ]; then
    echo "  -> Consolidando /lib en /usr/lib (UsrMerge)..."
    cp -a "${ROOTFS_DIR}/lib/." "${ROOTFS_DIR}/usr/lib/"
    rm -rf "${ROOTFS_DIR}/lib"
    ln -s usr/lib "${ROOTFS_DIR}/lib"
fi

if [ ! -L "${ROOTFS_DIR}/lib64" ]; then
    rm -rf "${ROOTFS_DIR}/lib64"
    ln -s usr/lib "${ROOTFS_DIR}/lib64"
fi

# Verificar la existencia de enlaces críticos
[ -L "${ROOTFS_DIR}/bin" ] || ln -s usr/bin "${ROOTFS_DIR}/bin"
[ -L "${ROOTFS_DIR}/sbin" ] || ln -s usr/sbin "${ROOTFS_DIR}/sbin"

# Enlace directo para init
ln -sf /lib/systemd/systemd "${ROOTFS_DIR}/init"

# Detectar binario QEMU aarch64 (sistema o local)
QEMU_BIN="$(command -v qemu-aarch64-static || echo "${TOOLS_DIR}/usr/bin/qemu-aarch64-static")"

# Generar loaders.cache de gdk-pixbuf con soporte PNG y SVG
echo "  -> Generando loaders.cache de gdk-pixbuf..."
mkdir -p "${ROOTFS_DIR}/usr/lib/aarch64-linux-gnu/gdk-pixbuf-2.0/2.10.0"
"${QEMU_BIN}" -L "${ROOTFS_DIR}" "${ROOTFS_DIR}/usr/lib/aarch64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders" > "${ROOTFS_DIR}/usr/lib/aarch64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache" 2>/dev/null || true

# Generar cache de MIME y fuentes
echo "  -> Generando cache de MIME y fuentes..."
mkdir -p "${ROOTFS_DIR}/var/cache/fontconfig"
chmod 777 "${ROOTFS_DIR}/var/cache/fontconfig"
"${QEMU_BIN}" -L "${ROOTFS_DIR}" "${ROOTFS_DIR}/usr/bin/update-mime-database" "${ROOTFS_DIR}/usr/share/mime" 2>/dev/null || true
"${QEMU_BIN}" -L "${ROOTFS_DIR}" "${ROOTFS_DIR}/usr/bin/fc-cache" -f 2>/dev/null || true

# Generar cache de temas de iconos GTK
echo "  -> Generando cache de temas de iconos GTK..."
"${QEMU_BIN}" -L "${ROOTFS_DIR}" "${ROOTFS_DIR}/usr/bin/gtk-update-icon-cache" -f -t "${ROOTFS_DIR}/usr/share/icons/hicolor" 2>/dev/null || true
"${QEMU_BIN}" -L "${ROOTFS_DIR}" "${ROOTFS_DIR}/usr/bin/gtk-update-icon-cache" -f -t "${ROOTFS_DIR}/usr/share/icons/Adwaita" 2>/dev/null || true

# Compilar esquemas GSettings de GLib
echo "  -> Compilando esquemas GSettings de GLib..."
glib-compile-schemas "${ROOTFS_DIR}/usr/share/glib-2.0/schemas/" 2>/dev/null || \
"${QEMU_BIN}" -L "${ROOTFS_DIR}" "${ROOTFS_DIR}/usr/lib/aarch64-linux-gnu/glib-2.0/glib-compile-schemas" "${ROOTFS_DIR}/usr/share/glib-2.0/schemas/" 2>/dev/null || true



# 1. Machine-ID y Desactivación de Firstboot
rm -f "${ROOTFS_DIR}/etc/machine-id"
echo "c58a8e52e4724c94b7f846175e2a6d10" > "${ROOTFS_DIR}/etc/machine-id"
rm -f "${ROOTFS_DIR}/usr/lib/systemd/system/sysinit.target.wants/systemd-firstboot.service"
mkdir -p "${ROOTFS_DIR}/var/lib/dbus"
ln -sf /etc/machine-id "${ROOTFS_DIR}/var/lib/dbus/machine-id"
echo "LANG=C.UTF-8" > "${ROOTFS_DIR}/etc/default/locale"
echo "LC_ALL=C.UTF-8" >> "${ROOTFS_DIR}/etc/default/locale"

# 2. Configuración de LightDM con Autologin a XFCE y Greeter GTK
mkdir -p "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d" "${ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d" "${ROOTFS_DIR}/etc/systemd/system" "${ROOTFS_DIR}/etc/X11"

cat << 'EOF' > "${ROOTFS_DIR}/etc/lightdm/lightdm.conf"
[LightDM]
run-directory=/run/lightdm

[Seat:*]
autologin-user=switch
autologin-user-timeout=0
user-session=xfce
greeter-session=lightdm-gtk-greeter
greeter-show-manual-login=false
autologin-inhibit=false
xserver-command=X -core -noreset -keeptty -ignoreABI
EOF

# Configuración complementaria en conf.d para asegurar precedencia
cat << 'EOF' > "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d/10-switch-autologin.conf"
[Seat:*]
autologin-user=switch
autologin-user-timeout=0
user-session=xfce
greeter-session=lightdm-gtk-greeter
greeter-show-manual-login=false
autologin-inhibit=false
xserver-command=X -core -noreset -keeptty -ignoreABI
EOF

cat << 'EOF' > "${ROOTFS_DIR}/usr/share/lightdm/lightdm.conf.d/99-switch-autologin.conf"
[Seat:*]
autologin-user=switch
autologin-user-timeout=0
user-session=xfce
greeter-session=lightdm-gtk-greeter
greeter-show-manual-login=false
autologin-inhibit=false
xserver-command=X -core -noreset -keeptty -ignoreABI
EOF

# Configuración del Greeter GTK
cat << 'EOF' > "${ROOTFS_DIR}/etc/lightdm/lightdm-gtk-greeter.conf"
[greeter]
theme-name=Adwaita
icon-theme-name=Adwaita
cursor-theme-name=Adwaita
font-name=Sans 10
xft-antialias=true
xft-dpi=96
xft-hintstyle=hintslight
xft-rgba=rgb
default-session=xfce
keyboard=onboard
EOF

# Asegurar symlink alternativo de greeter para Debian (lightdm-greeter.desktop)
mkdir -p "${ROOTFS_DIR}/usr/share/xgreeters"
ln -sf lightdm-gtk-greeter.desktop "${ROOTFS_DIR}/usr/share/xgreeters/lightdm-greeter.desktop" 2>/dev/null || true

# Indicar default-display-manager a nivel de sistema X11
echo "/usr/sbin/lightdm" > "${ROOTFS_DIR}/etc/X11/default-display-manager"

rm -rf "${ROOTFS_DIR}/etc/systemd/system/lightdm.service.d"
rm -f "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service"

ln -sf /lib/systemd/system/lightdm.service "${ROOTFS_DIR}/etc/systemd/system/display-manager.service"
ln -sf /lib/systemd/system/graphical.target "${ROOTFS_DIR}/etc/systemd/system/default.target"

# Reglas UDEV para que systemd-logind reconozca el Framebuffer como pantalla gráfica maestra (master-of-seat)
mkdir -p "${ROOTFS_DIR}/etc/udev/rules.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/udev/rules.d/71-tegra-seat.rules"
# Asignar Framebuffer de Tegra y DRM como dispositivos graficos maestros de seat0
SUBSYSTEM=="graphics", KERNEL=="fb*", TAG+="seat", TAG+="master-of-seat", TAG+="uaccess"
SUBSYSTEM=="drm", KERNEL=="card*", TAG+="seat", TAG+="master-of-seat", TAG+="uaccess"
EOF

# Desactivar serial-getty@ttyGS0 para evitar esperas y timeouts en el arranque
ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/serial-getty@ttyGS0.service"

# 3. Configuración Xorg y Xwrapper para permisos y pantalla Tegra con RandR nativo
mkdir -p "${ROOTFS_DIR}/etc/X11/xorg.conf.d"
rm -f "${ROOTFS_DIR}/etc/X11/xorg.conf.d/10-rotate.conf"
rm -f "${ROOTFS_DIR}/etc/X11/xorg.conf.d/99-switch.conf"

cat << 'EOF' > "${ROOTFS_DIR}/etc/X11/Xwrapper.config"
allowed_users=anybody
needs_root_rights=yes
EOF

cat << 'EOF' > "${ROOTFS_DIR}/etc/X11/xorg.conf"
# Copyright (c) 2011-2013 NVIDIA CORPORATION.  All Rights Reserved.

Section "Module"
    Disable     "dri"
    SubSection  "extmod"
        Option  "omit xfree86-dga"
    EndSubSection
EndSection

Section "Device"
    Identifier  "Tegra0"
    Driver      "nvidia"
    Option      "AllowUnofficialGLXProtocol" "true"
    Option      "DPMS" "false"
    Option      "AllowEmptyInitialConfiguration" "true"
    Option      "Monitor-DSI-0" "Monitor0"
    Option      "Monitor-DP-0" "Monitor1"
EndSection
EOF

cat << 'EOF' > "${ROOTFS_DIR}/etc/X11/xorg.conf.d/10-monitor.conf"
Section "Monitor"
   Identifier  "Monitor0"
   ModelName   "DFP-0"
EndSection

Section "Monitor"
   Identifier  "Monitor1"
   Option      "Enable" "false"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Tegra0"
    Monitor        "Monitor0"
    DefaultDepth   24
    Option         "metamodes" "DSI-0: nvidia-auto-select @1280x720 +0+0 {ViewPortIn=1280x720, ViewPortOut=1280x720+0+0, Rotation=0}"
    SubSection     "Display"
        Depth      24
    EndSubSection
EndSection
EOF

mkdir -p "${ROOTFS_DIR}/etc/X11/xorg.conf.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/X11/xorg.conf.d/50-switch-touchscreen.conf"
Section "InputClass"
    Identifier "Switch STMFTS Touchscreen"
    MatchProduct "st_stmfts_touchscreen"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "TransformationMatrix" "0 -1 1 1 0 0 0 0 1"
    Option "SendCoreEvents" "true"
    Option "TapButton1" "1"
EndSection

Section "InputClass"
    Identifier "Switch Goodix Touchscreen"
    MatchProduct "Goodix Capacitive TouchScreen"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "TransformationMatrix" "0 -1 1 1 0 0 0 0 1"
EndSection

Section "InputClass"
    Identifier "Switch Touchscreen Generic"
    MatchProduct "touchscreen"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "TransformationMatrix" "0 -1 1 1 0 0 0 0 1"
EndSection
EOF

# 4. Teclado Virtual en Pantalla (Onboard) en Autostart de XFCE
mkdir -p "${ROOTFS_DIR}/etc/xdg/autostart"
cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/autostart/onboard.desktop"
[Desktop Entry]
Type=Application
Name=Onboard
Exec=onboard
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# 5. Configuración de usuarios del sistema (lightdm, switch) y contraseñas (contraseña: switch)
USER_HASH=$(openssl passwd -6 "switch")

# Usuario del sistema lightdm
if ! grep -q "^lightdm:" "${ROOTFS_DIR}/etc/passwd"; then
    echo "lightdm:x:105:110:Light Display Manager:/var/lib/lightdm:/bin/false" >> "${ROOTFS_DIR}/etc/passwd"
fi
if ! grep -q "^lightdm:" "${ROOTFS_DIR}/etc/group"; then
    echo "lightdm:x:110:" >> "${ROOTFS_DIR}/etc/group"
fi
if ! grep -q "^lightdm:" "${ROOTFS_DIR}/etc/shadow"; then
    echo "lightdm:*:19800:0:99999:7:::" >> "${ROOTFS_DIR}/etc/shadow"
fi

mkdir -p "${ROOTFS_DIR}/var/lib/lightdm/data" "${ROOTFS_DIR}/var/cache/lightdm" "${ROOTFS_DIR}/var/log/lightdm" "${ROOTFS_DIR}/run/lightdm"
chown -R 105:110 "${ROOTFS_DIR}/var/lib/lightdm" "${ROOTFS_DIR}/var/cache/lightdm" "${ROOTFS_DIR}/run/lightdm" 2>/dev/null || true
chmod 755 "${ROOTFS_DIR}/var/lib/lightdm" "${ROOTFS_DIR}/var/cache/lightdm" "${ROOTFS_DIR}/var/log/lightdm"
chmod 750 "${ROOTFS_DIR}/var/lib/lightdm/data"

# Usuario switch
if ! grep -q "^switch:" "${ROOTFS_DIR}/etc/passwd"; then
    echo "switch:x:1000:1000:Nintendo Switch User,,,:/home/switch:/bin/bash" >> "${ROOTFS_DIR}/etc/passwd"
fi

for grp in sudo audio video input render plugdev users dialout netdev autologin nopasswdlogin bluetooth; do
    if grep -q "^${grp}:" "${ROOTFS_DIR}/etc/group"; then
        sed -i "s/^${grp}:.*/&,switch/" "${ROOTFS_DIR}/etc/group"
        sed -i "s/:,switch/:switch/" "${ROOTFS_DIR}/etc/group"
    else
        echo "${grp}:x:999:switch" >> "${ROOTFS_DIR}/etc/group"
    fi
done
grep -q "^switch:" "${ROOTFS_DIR}/etc/group" || echo "switch:x:1000:" >> "${ROOTFS_DIR}/etc/group"

if [ -f "${ROOTFS_DIR}/etc/adduser.conf" ]; then
    sed -i 's|^#*ADD_EXTRA_GROUPS=.*|ADD_EXTRA_GROUPS=1|' "${ROOTFS_DIR}/etc/adduser.conf"
    sed -i 's|^#*EXTRA_GROUPS=.*|EXTRA_GROUPS="sudo audio video input render plugdev users dialout netdev bluetooth"|' "${ROOTFS_DIR}/etc/adduser.conf"
fi

sed -i "s|^root:.*|root:*:19800:0:99999:7:::|" "${ROOTFS_DIR}/etc/shadow"
if grep -q "^switch:" "${ROOTFS_DIR}/etc/shadow"; then
    sed -i "s|^switch:.*|switch:${USER_HASH}:19800:0:99999:7:::|" "${ROOTFS_DIR}/etc/shadow"
else
    echo "switch:${USER_HASH}:19800:0:99999:7:::" >> "${ROOTFS_DIR}/etc/shadow"
fi

mkdir -p "${ROOTFS_DIR}/home/switch"
cp "${ROOTFS_DIR}/etc/skel"/.bash* "${ROOTFS_DIR}/home/switch/" 2>/dev/null || true
cp "${ROOTFS_DIR}/etc/skel"/.profile "${ROOTFS_DIR}/home/switch/" 2>/dev/null || true

# 5. Utilidad de Rotación de Pantalla y Táctil en Caliente (On-the-Fly)
mkdir -p "${ROOTFS_DIR}/usr/local/bin" "${ROOTFS_DIR}/usr/share/applications"
cat << 'EOF' > "${ROOTFS_DIR}/usr/local/bin/switch-rotate"
#!/bin/bash
# switch-rotate: Rotación instantánea en caliente (on-the-fly) de pantalla y panel táctil para Nintendo Switch
# Aplica de golpe usando XRandR y libinput sin necesidad de reiniciar la consola ni la sesión gráfica.

MODE="$1"

# Directorio de configuración de usuario
USER_CFG_DIR="${HOME:-/home/switch}/.config"
STATE_FILE="${USER_CFG_DIR}/switch-rotation"
mkdir -p "${USER_CFG_DIR}" 2>/dev/null || true

# Detectar salida de pantalla activa conectada
DISP=$(xrandr --query 2>/dev/null | grep ' connected' | awk '{print $1}' | head -n 1)
[ -z "$DISP" ] && DISP="DSI-0"

# Obtener orientación actual (desde archivo de estado o consultando a xrandr)
if [ -f "$STATE_FILE" ]; then
    CUR=$(cat "$STATE_FILE" 2>/dev/null | tr -d ' \n\r')
else
    CUR=$(xrandr --query --verbose 2>/dev/null | grep -A 5 "^$DISP" | grep -oE '(normal|left|inverted|right)' | head -n 1)
fi
[ -z "$CUR" ] && CUR="normal"

# Ciclo automático cuando se ejecuta sin parámetros o con "next"
if [ -z "$MODE" ] || [ "$MODE" = "next" ]; then
    case "$CUR" in
        "normal"|"landscape")        MODE="left" ;;
        "left"|"portrait")           MODE="inverted" ;;
        "inverted"|"inv-landscape")  MODE="right" ;;
        "right"|"inv-portrait")      MODE="normal" ;;
        *)                           MODE="normal" ;;
    esac
fi

# Mapeo de orientación y matriz de transformación táctil (Coordinate Transformation Matrix)
case "$MODE" in
    "normal"|"landscape"|"0")
        ROT="normal"
        TMAT="1 0 0 0 1 0 0 0 1"
        NAME="Landscape"
        ;;
    "left"|"portrait"|"90")
        ROT="left"
        TMAT="0 -1 1 1 0 0 0 0 1"
        NAME="Portrait"
        ;;
    "inverted"|"inv-landscape"|"180")
        ROT="inverted"
        TMAT="-1 0 1 0 -1 1 0 0 1"
        NAME="Inverted Landscape"
        ;;
    "right"|"inv-portrait"|"270")
        ROT="right"
        TMAT="0 1 0 -1 0 1 0 0 1"
        NAME="Inverted Portrait"
        ;;
    *)
        ROT="normal"
        TMAT="1 0 0 0 1 0 0 0 1"
        NAME="Landscape"
        ;;
esac

# 1. Rotación instantánea de la pantalla con XRandR
xrandr --output "$DISP" --rotate "$ROT" 2>/dev/null || xrandr -o "$ROT" 2>/dev/null || true

# 2. Rotación instantánea del sensor táctil en libinput
for dev in $(xinput list --name-only 2>/dev/null | grep -iE "(touch|fts|goodix|touchscreen)"); do
    xinput set-prop "$dev" --type=float "Coordinate Transformation Matrix" $TMAT 2>/dev/null || true
done

# 3. Guardar estado para que persista automáticamente entre reinicios
echo "$ROT" > "$STATE_FILE" 2>/dev/null || true
echo "$ROT" > "/etc/default/switch-rotation" 2>/dev/null || true

# 4. Immediate desktop notification in English
which notify-send >/dev/null 2>&1 && notify-send -t 2500 -i display "Screen Orientation" "Orientation: $NAME\nApplied immediately" 2>/dev/null || true
EOF
chmod 755 "${ROOTFS_DIR}/usr/local/bin/switch-rotate"

cat << 'EOF' > "${ROOTFS_DIR}/usr/share/applications/switch-rotate.desktop"
[Desktop Entry]
Type=Application
Name=Rotate Screen
Comment=Rotate display and touch orientation (Landscape / Portrait)
Exec=/usr/local/bin/switch-rotate next
Icon=display
Terminal=false
Categories=Settings;HardwareSettings;System;
EOF

# Script para reactivar la pantalla de Nintendo Switch al reanudar de suspensión
mkdir -p "${ROOTFS_DIR}/lib/systemd/system-sleep" "${ROOTFS_DIR}/usr/lib/systemd/system-sleep"
cat << 'EOF' > "${ROOTFS_DIR}/lib/systemd/system-sleep/99-switch-display-wake.sh"
#!/bin/sh
# Wake up Nintendo Switch display on resume from sleep
case "$1/$2" in
  post/*)
    # Despertar y desblanquear el Framebuffer
    echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null || true
    # Forzar refresco de VT para sincronizar el rasterizador del Display Controller
    if which chvt >/dev/null 2>&1; then
      chvt 2 >/dev/null 2>&1
      sleep 0.05
      chvt 1 >/dev/null 2>&1
    fi
    # Despertar X11 DPMS
    DISPLAY=:0 xset dpms force on 2>/dev/null || true
    ;;
esac
exit 0
EOF
chmod 755 "${ROOTFS_DIR}/lib/systemd/system-sleep/99-switch-display-wake.sh"
ln -sf /lib/systemd/system-sleep/99-switch-display-wake.sh "${ROOTFS_DIR}/usr/lib/systemd/system-sleep/99-switch-display-wake.sh" 2>/dev/null || true

# Pre-configuración de XFCE4: Tema, Iconos, Panel y Applets
mkdir -p "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "${ROOTFS_DIR}/etc/xdg/xfce4/panel"
mkdir -p "${ROOTFS_DIR}/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "${ROOTFS_DIR}/home/switch/.config/xfce4/xfconf/xfce-perchannel-xml"

# 1. Configuración de Apariencia y Tema de Iconos Adwaita
cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
    <property name="DoubleClickTime" type="int" value="400"/>
    <property name="DoubleClickDistance" type="int" value="5"/>
    <property name="DndDragThreshold" type="int" value="8"/>
    <property name="CursorBlink" type="bool" value="true"/>
    <property name="CursorBlinkTime" type="int" value="1200"/>
    <property name="SoundThemeName" type="string" value="default"/>
    <property name="EnableEventSounds" type="bool" value="false"/>
    <property name="EnableInputFeedbackSounds" type="bool" value="false"/>
  </property>
  <property name="Xft" type="empty">
    <property name="DPI" type="int" value="96"/>
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Sans 10"/>
    <property name="MonospaceFontName" type="string" value="Monospace 10"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorThemeSize" type="int" value="24"/>
    <property name="DecorationLayout" type="string" value="menu:minimize,maximize,close"/>
  </property>
</channel>
EOF
cp "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" "${ROOTFS_DIR}/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
cp "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" "${ROOTFS_DIR}/home/switch/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"

# 2. Configuración del Panel XFCE4 con Soporte Completo de Bandeja del Sistema
cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <value type="int" value="2"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="16"/>
      <property name="size" type="uint" value="28"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
      </property>
    </property>
    <property name="panel-2" type="empty">
      <property name="autohide-behavior" type="uint" value="1"/>
      <property name="position" type="string" value="p=10;x=0;y=0"/>
      <property name="length" type="uint" value="1"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="48"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="11"/>
        <value type="int" value="12"/>
        <value type="int" value="13"/>
        <value type="int" value="14"/>
        <value type="int" value="15"/>
        <value type="int" value="16"/>
        <value type="int" value="17"/>
        <value type="int" value="18"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu"/>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="1"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="switch-rotate.desktop"/>
      </property>
    </property>
    <property name="plugin-5" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
    </property>
    <property name="plugin-6" type="string" value="power-manager-plugin"/>
    <property name="plugin-7" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
      <property name="single-row" type="bool" value="true"/>
      <property name="hide-new-items" type="bool" value="false"/>
      <property name="symbolic-icons" type="bool" value="false"/>
    </property>
    <property name="plugin-8" type="string" value="indicator"/>
    <property name="plugin-9" type="string" value="clock"/>
    <property name="plugin-10" type="string" value="actions"/>
    <property name="plugin-11" type="string" value="showdesktop"/>
    <property name="plugin-12" type="string" value="separator"/>
    <property name="plugin-13" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-terminal-emulator.desktop"/>
      </property>
    </property>
    <property name="plugin-14" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-file-manager.desktop"/>
      </property>
    </property>
    <property name="plugin-15" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-web-browser.desktop"/>
      </property>
    </property>
    <property name="plugin-16" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-appfinder.desktop"/>
      </property>
    </property>
    <property name="plugin-17" type="string" value="separator"/>
    <property name="plugin-18" type="string" value="directorymenu"/>
  </property>
</channel>
EOF

cp "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" "${ROOTFS_DIR}/etc/xdg/xfce4/panel/default.xml"
cp "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" "${ROOTFS_DIR}/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
cp "${ROOTFS_DIR}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" "${ROOTFS_DIR}/home/switch/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"

# Limpieza de archivos obsoletos en /etc/skel
rm -f "${ROOTFS_DIR}/etc/skel/.config/monitors.xml"
rm -f "${ROOTFS_DIR}/etc/skel/.config/unity-monitors.xml"
rm -f "${ROOTFS_DIR}/etc/skel/.face" "${ROOTFS_DIR}/etc/skel/.face.icon"

# Configurar rotación de pantalla en Xsession antes de iniciar el entorno de escritorio
mkdir -p "${ROOTFS_DIR}/etc/X11/Xsession.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/X11/Xsession.d/45switch-rotation"
# /etc/X11/Xsession.d/45switch-rotation
# Ensure Nintendo Switch display rotation and touch mapping are active before session starts
if [ -x /usr/local/bin/switch-rotate ]; then
    if [ -f "${HOME}/.config/switch-rotation" ]; then
        /usr/local/bin/switch-rotate "$(cat "${HOME}/.config/switch-rotation")" >/dev/null 2>&1 || true
    elif [ -f "/etc/default/switch-rotation" ]; then
        /usr/local/bin/switch-rotate "$(cat "/etc/default/switch-rotation")" >/dev/null 2>&1 || true
    fi
fi
EOF
chmod 644 "${ROOTFS_DIR}/etc/X11/Xsession.d/45switch-rotation"

# 3. Script de inicio coordinado para applets de WiFi, Bluetooth, Overclock y Batería
mkdir -p "${ROOTFS_DIR}/usr/local/bin"
cat << 'EOF' > "${ROOTFS_DIR}/usr/local/bin/switch-desktop-autostart.sh"
#!/bin/bash
# switch-desktop-autostart.sh: background services for Switchroot Debian

# 1. Desbloquear y activar radios inalámbricas
rfkill unblock all 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true
bluetoothctl power on 2>/dev/null || true

# 2. Iniciar applet de red NetworkManager (WiFi) en bandeja
if ! pgrep -x nm-applet >/dev/null 2>&1; then
    nm-applet &
fi

# 3. Iniciar applet de Bluetooth Blueman en bandeja
if ! pgrep -x blueman-applet >/dev/null 2>&1; then
    blueman-applet &
fi

# 4. Iniciar gestor de energía (Nivel y estado de batería)
if ! pgrep -x xfce4-power-manager >/dev/null 2>&1; then
    xfce4-power-manager &
fi

# 6. Iniciar suite de Overclock, Perfiles y Protección de Batería (NVPModel)
if [ -x /usr/share/nvpmodel_indicator/nvpmodel_indicator.py ] && ! pgrep -f nvpmodel_indicator.py >/dev/null 2>&1; then
    python3 /usr/share/nvpmodel_indicator/nvpmodel_indicator.py &
fi
EOF
chmod 755 "${ROOTFS_DIR}/usr/local/bin/switch-desktop-autostart.sh"

# Helper para escaneo visual directo de WiFi en terminal
cat << 'EOF' > "${ROOTFS_DIR}/usr/local/bin/switch-wifi-scan.sh"
#!/bin/bash
clear
echo "========================================================"
echo "    Nintendo Switch - Escáner de Redes WiFi (Debian 13)"
echo "========================================================"
echo ""
echo "[*] Desbloqueando rfkill..."
rfkill unblock wifi
echo "[*] Encendiendo antena WiFi (nmcli radio wifi on)..."
nmcli radio wifi on
echo "[*] Escaneando redes WiFi disponibles en el entorno..."
nmcli --fields SSID,BSSID,MODE,CHAN,FREQ,RATE,SIGNAL,BARS,SECURITY dev wifi list --rescan yes
echo ""
echo "========================================================"
echo "Pulsa [ENTER] para abrir el Gestor Gráfico de Conexiones WiFi..."
read -r
nm-connection-editor &
EOF
chmod 755 "${ROOTFS_DIR}/usr/local/bin/switch-wifi-scan.sh"

# Autostart para nm-applet, blueman y power manager sin restricciones de escritorio
mkdir -p "${ROOTFS_DIR}/etc/xdg/autostart"
cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/autostart/switch-desktop-autostart.desktop"
[Desktop Entry]
Type=Application
Name=Switch Applets Autostart
Comment=Start WiFi, Bluetooth and Onboard Applets
Exec=/usr/local/bin/switch-desktop-autostart.sh
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/autostart/nm-applet.desktop"
[Desktop Entry]
Name=Network
Comment=Manage your network connections
Icon=nm-device-wireless
Exec=nm-applet
Terminal=false
Type=Application
NoDisplay=false
Hidden=false
EOF

cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/autostart/blueman.desktop"
[Desktop Entry]
Name=Bluetooth Manager
Comment=Manage Bluetooth devices
Icon=blueman
Exec=blueman-applet
Terminal=false
Type=Application
NoDisplay=false
Hidden=false
EOF

# Desactivar xapp-sn-watcher para que libsystray sea el dueño legítimo de StatusNotifierWatcher
if [ -f "${ROOTFS_DIR}/etc/xdg/autostart/xapp-sn-watcher.desktop" ]; then
    echo "Hidden=true" >> "${ROOTFS_DIR}/etc/xdg/autostart/xapp-sn-watcher.desktop"
    echo "NoDisplay=true" >> "${ROOTFS_DIR}/etc/xdg/autostart/xapp-sn-watcher.desktop"
fi

# Configurar autostart de suite NVPModel (Overclock y Protección de Batería)
cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/autostart/nvpmodel_indicator.desktop"
[Desktop Entry]
Name=NVIDIA nvpmodel indicator
GenericName=Overclock & Power Profiles
Comment=Indicator for power profiles, fan and battery charging protection
Exec=python3 /usr/share/nvpmodel_indicator/nvpmodel_indicator.py
Icon=/usr/share/nvpmodel_indicator/nvpmodel-switch.svg
Terminal=false
Type=Application
Categories=System;Settings;
EOF
chmod 644 "${ROOTFS_DIR}/etc/xdg/autostart/nvpmodel_indicator.desktop"
chmod 644 "${ROOTFS_DIR}/etc/xdg/autostart/switch-desktop-autostart.desktop"

# Desactivar arranque de teclado virtual Onboard al iniciar sesión
rm -f "${ROOTFS_DIR}/etc/xdg/autostart/onboard.desktop" 2>/dev/null || true
rm -f "${ROOTFS_DIR}/etc/xdg/autostart/onboard-autostart.desktop" 2>/dev/null || true

# Accesos directos en el menú de aplicaciones del sistema (panel / app menu)
mkdir -p "${ROOTFS_DIR}/usr/share/applications"
cat << 'EOF' > "${ROOTFS_DIR}/usr/share/applications/switch-wifi-scan.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Escáner de Redes WiFi
Comment=Escanear y mostrar redes WiFi en pantalla
Exec=xfce4-terminal --title="Escáner WiFi Switch" --hold -e /usr/local/bin/switch-wifi-scan.sh
Icon=network-wireless
Terminal=false
Categories=Network;
EOF

# Mantener el Escritorio completamente despejado y limpio
mkdir -p "${ROOTFS_DIR}/home/switch/Desktop" "${ROOTFS_DIR}/etc/skel/Desktop"
rm -f "${ROOTFS_DIR}/home/switch/Desktop"/* 2>/dev/null || true
rm -f "${ROOTFS_DIR}/etc/skel/Desktop"/* 2>/dev/null || true
chmod 755 "${ROOTFS_DIR}/home/switch/Desktop" 2>/dev/null || true
chmod 755 "${ROOTFS_DIR}/etc/skel/Desktop" 2>/dev/null || true

# Configurar .xsessionrc y .xinitrc para sesión limpia de XFCE
cat << 'EOF' > "${ROOTFS_DIR}/home/switch/.xsessionrc"
# Sesión de usuario XFCE
export XDG_CURRENT_DESKTOP=XFCE
EOF
chmod 755 "${ROOTFS_DIR}/home/switch/.xsessionrc"
cp "${ROOTFS_DIR}/home/switch/.xsessionrc" "${ROOTFS_DIR}/etc/skel/.xsessionrc"

cat << 'EOF' > "${ROOTFS_DIR}/home/switch/.xinitrc"
#!/bin/sh
xsetroot -solid "#222222"
exec startxfce4
EOF
chmod 755 "${ROOTFS_DIR}/home/switch/.xinitrc"
cp "${ROOTFS_DIR}/home/switch/.xinitrc" "${ROOTFS_DIR}/etc/skel/.xinitrc"

# Deshabilitar servicios conflictivos de red, getty duplicado y servicios muertos de Jetson
rm -rf "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d"
rm -rf "${ROOTFS_DIR}/etc/systemd/system/getty@tty0.service.d"
rm -f "${ROOTFS_DIR}/lib/systemd/system/bluetooth.service.d/nv-bluetooth-service.conf"
rm -f "${ROOTFS_DIR}/usr/lib/systemd/system/bluetooth.service.d/nv-bluetooth-service.conf"
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nv-l4t-usb-device-mode.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nvgetty.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants/systemd-network-generator.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants/systemd-resolved.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nvweston.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nvfb.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nvfb-early.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nvphs.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nvs-service.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nvzramconfig.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nvmemwarning.service"
rm -f "${ROOTFS_DIR}/etc/modprobe.d/tegra-udrm.conf"
rm -f "${ROOTFS_DIR}/etc/xdg/autostart"/nv*.sh
rm -f "${ROOTFS_DIR}/etc/xdg/autostart"/nv*.desktop
rm -f "${ROOTFS_DIR}/etc/xdg/autostart/nintendo-switch-display.desktop"

# Enmascarar systemd-networkd y systemd-resolved para que NetworkManager tenga control total
mkdir -p "${ROOTFS_DIR}/etc/systemd/system"
ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/systemd-networkd.service"
ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/systemd-networkd.socket"
ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/systemd-network-generator.service"
ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/systemd-resolved.service"

# Eliminar el timeout de 90 segundos de ttyGS0 en el arranque
rm -f "${ROOTFS_DIR}/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service"
ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/serial-getty@ttyGS0.service"

# Eliminar nvwifibt conflictivo con el driver serdev nativo del kernel
rm -f "${ROOTFS_DIR}/etc/udev/rules.d/99-nv-wifibt.rules"
ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/nvwifibt.service"

# Configurar Netplan para delegar todo el control de interfaces a NetworkManager
mkdir -p "${ROOTFS_DIR}/etc/netplan"
rm -f "${ROOTFS_DIR}/etc/netplan"/*.yaml
cat << 'EOF' > "${ROOTFS_DIR}/etc/netplan/01-network-manager.yaml"
network:
  version: 2
  renderer: NetworkManager
EOF
chmod 600 "${ROOTFS_DIR}/etc/netplan/01-network-manager.yaml"

# 6. Permisos Sudo y SUID obligatorios
mkdir -p "${ROOTFS_DIR}/etc/sudoers.d"
echo "switch ALL=(ALL:ALL) NOPASSWD: ALL" > "${ROOTFS_DIR}/etc/sudoers.d/010_switch-nopasswd"
chmod 0440 "${ROOTFS_DIR}/etc/sudoers.d/010_switch-nopasswd"
chmod 0440 "${ROOTFS_DIR}/etc/sudoers"

chmod 4755 "${ROOTFS_DIR}/usr/bin/sudo"
chmod 4755 "${ROOTFS_DIR}/usr/bin/su"
chmod 4755 "${ROOTFS_DIR}/usr/bin/passwd"
chmod 4755 "${ROOTFS_DIR}/usr/bin/gpasswd"
chmod 4755 "${ROOTFS_DIR}/usr/bin/newgrp"
chmod 4755 "${ROOTFS_DIR}/usr/bin/chsh"
chmod 4755 "${ROOTFS_DIR}/usr/bin/chfn"
chmod 4755 "${ROOTFS_DIR}/usr/lib/xorg/Xorg"
chmod 4754 "${ROOTFS_DIR}/usr/lib/dbus-1.0/dbus-daemon-launch-helper" 2>/dev/null || true

# Permisos para directorios temporales y home
mkdir -p "${ROOTFS_DIR}/tmp" "${ROOTFS_DIR}/var/tmp"
chmod 1777 "${ROOTFS_DIR}/tmp" "${ROOTFS_DIR}/var/tmp"
chown -R 1000:1000 "${ROOTFS_DIR}/home/switch"
chmod 755 "${ROOTFS_DIR}/home/switch"

# Firmware Broadcom BCM4356 (WiFi / Bluetooth) y perfiles de Audio
mkdir -p "${ROOTFS_DIR}/usr/lib/firmware/brcm" "${ROOTFS_DIR}/lib/firmware/brcm"
if [ -d "${DOWNLOADS_DIR}/switch-firmware/brcm" ]; then
    cp -rf "${DOWNLOADS_DIR}/switch-firmware/brcm"/* "${ROOTFS_DIR}/usr/lib/firmware/brcm/"
    cp -rf "${DOWNLOADS_DIR}/switch-firmware/brcm"/* "${ROOTFS_DIR}/lib/firmware/brcm/"
fi

# Enlaces y variantes de Device Tree para WiFi Broadcom
if [ -f "${ROOTFS_DIR}/usr/lib/firmware/brcm/brcmfmac4356A3-pcie.bin" ]; then
    ln -sf brcmfmac4356A3-pcie.bin "${ROOTFS_DIR}/usr/lib/firmware/brcm/brcmfmac4356-pcie.bin"
    ln -sf brcmfmac4356A3-pcie.bin "${ROOTFS_DIR}/lib/firmware/brcm/brcmfmac4356-pcie.bin"
fi

if [ -f "${ROOTFS_DIR}/usr/lib/firmware/brcm/brcmfmac4356A3-pcie.txt" ]; then
    ln -sf brcmfmac4356A3-pcie.txt "${ROOTFS_DIR}/usr/lib/firmware/brcm/brcmfmac4356-pcie.txt"
    ln -sf brcmfmac4356A3-pcie.txt "${ROOTFS_DIR}/lib/firmware/brcm/brcmfmac4356-pcie.txt"
    for fw in brcmfmac4356-pcie.nintendo,switch.txt brcmfmac4356-pcie.nintendo,odin.txt brcmfmac4356-pcie.nintendo,vali.txt brcmfmac4356-pcie.nintendo,fric.txt; do
        cp -f "${ROOTFS_DIR}/usr/lib/firmware/brcm/brcmfmac4356A3-pcie.txt" "${ROOTFS_DIR}/usr/lib/firmware/brcm/${fw}"
        cp -f "${ROOTFS_DIR}/usr/lib/firmware/brcm/brcmfmac4356A3-pcie.txt" "${ROOTFS_DIR}/lib/firmware/brcm/${fw}"
    done
fi

# Firmware Bluetooth Broadcom
if [ -f "${ROOTFS_DIR}/usr/lib/firmware/brcm/BCM4356A3.hcd" ]; then
    ln -sf BCM4356A3.hcd "${ROOTFS_DIR}/usr/lib/firmware/brcm/bcm4356.hcd"
    ln -sf brcm/BCM4356A3.hcd "${ROOTFS_DIR}/usr/lib/firmware/bcm4356.hcd"
    ln -sf BCM4356A3.hcd "${ROOTFS_DIR}/lib/firmware/brcm/bcm4356.hcd"
    ln -sf brcm/BCM4356A3.hcd "${ROOTFS_DIR}/lib/firmware/bcm4356.hcd"
fi
NOBLE_ROOT="${CWD}/theofficialgman-ubuntu-unity-noble-5.1.2-2026-05-13/switchroot/install/contenido_completo"

# Audio: Copiar árbol maestro completo de ALSA UCM2, asound.conf y reglas de Noble
mkdir -p "${ROOTFS_DIR}/usr/share/alsa"
if [ -d "${NOBLE_ROOT}/usr/share/alsa/ucm2" ]; then
    echo "  -> Sincronizando árbol maestro ALSA UCM2 desde Noble..."
    cp -rn "${NOBLE_ROOT}/usr/share/alsa/ucm2"/* "${ROOTFS_DIR}/usr/share/alsa/ucm2/" 2>/dev/null || true
    cp -f "${NOBLE_ROOT}/usr/share/alsa/ucm2/ucm.conf" "${ROOTFS_DIR}/usr/share/alsa/ucm2/ucm.conf" 2>/dev/null || true
    [ -f "${NOBLE_ROOT}/usr/share/alsa/pulse-alsa.conf" ] && cp -f "${NOBLE_ROOT}/usr/share/alsa/pulse-alsa.conf" "${ROOTFS_DIR}/usr/share/alsa/" 2>/dev/null || true
fi
ln -sf ucm2 "${ROOTFS_DIR}/usr/share/alsa/ucm" 2>/dev/null || true

mkdir -p "${ROOTFS_DIR}/usr/share/alsa/ucm2/conf.d/tegra-snd-t210ref-mobile-rt565x"
mkdir -p "${ROOTFS_DIR}/usr/share/alsa/ucm2/conf.d/tegra-snd-t210r"
mkdir -p "${ROOTFS_DIR}/usr/share/alsa/ucm2/conf.d/tegra-hda"
ln -sf ../../Tegra/tegra-snd-t210ref-mobile-rt565x/tegra-snd-t210ref-mobile-rt565x.conf "${ROOTFS_DIR}/usr/share/alsa/ucm2/conf.d/tegra-snd-t210ref-mobile-rt565x/tegra-snd-t210ref-mobile-rt565x.conf" 2>/dev/null || true
ln -sf ../../Tegra/tegra-snd-t210ref-mobile-rt565x/tegra-snd-t210ref-mobile-rt565x.conf "${ROOTFS_DIR}/usr/share/alsa/ucm2/conf.d/tegra-snd-t210r/tegra-snd-t210ref-mobile-rt565x.conf" 2>/dev/null || true
ln -sf ../../Tegra/tegra-hda/tegra-hda.conf "${ROOTFS_DIR}/usr/share/alsa/ucm2/conf.d/tegra-hda/tegra-hda.conf" 2>/dev/null || true

if [ -f "${NOBLE_ROOT}/etc/asound.conf.tegrasndt210ref" ]; then
    cp -f "${NOBLE_ROOT}/etc/asound.conf.tegrasndt210ref" "${ROOTFS_DIR}/etc/asound.conf.tegrasndt210ref"
    cp -f "${NOBLE_ROOT}/etc/asound.conf.tegrahda" "${ROOTFS_DIR}/etc/asound.conf.tegrahda"
    ln -sf asound.conf.tegrasndt210ref "${ROOTFS_DIR}/etc/asound.conf"
fi

if [ -f "${NOBLE_ROOT}/etc/udev/rules.d/90-alsa-asound-tegra.rules.orig" ]; then
    cp -f "${NOBLE_ROOT}/etc/udev/rules.d/90-alsa-asound-tegra.rules.orig" "${ROOTFS_DIR}/etc/udev/rules.d/90-alsa-asound-tegra.rules"
fi

# Habilitar PulseAudio como servicio de usuario systemd y autostart
echo "  -> Habilitando servidor de sonido PulseAudio en systemd user session..."
mkdir -p "${ROOTFS_DIR}/etc/systemd/user/default.target.wants" "${ROOTFS_DIR}/etc/systemd/user/sockets.target.wants"
ln -sf /usr/lib/systemd/user/pulseaudio.service "${ROOTFS_DIR}/etc/systemd/user/default.target.wants/pulseaudio.service" 2>/dev/null || true
ln -sf /usr/lib/systemd/user/pulseaudio.socket "${ROOTFS_DIR}/etc/systemd/user/sockets.target.wants/pulseaudio.socket" 2>/dev/null || true

mkdir -p "${ROOTFS_DIR}/etc/pulse/client.conf.d"
rm -f "${ROOTFS_DIR}/etc/pulse/client.conf.d/01-enable-autospawn.conf"
cat << 'EOF' > "${ROOTFS_DIR}/etc/pulse/client.conf.d/01-enable-autospawn.conf"
autospawn = yes
EOF

if [ -f "${NOBLE_ROOT}/etc/xdg/autostart/pulseaudio.desktop" ]; then
    cp -f "${NOBLE_ROOT}/etc/xdg/autostart/pulseaudio.desktop" "${ROOTFS_DIR}/etc/xdg/autostart/pulseaudio.desktop"
fi

# Typelibs de GObject Introspection (xlib, cairo, notify, ayatana para applets)
mkdir -p "${ROOTFS_DIR}/usr/lib/aarch64-linux-gnu/girepository-1.0" "${ROOTFS_DIR}/usr/lib/girepository-1.0"
if [ -d "${NOBLE_ROOT}/usr/lib/aarch64-linux-gnu/girepository-1.0" ]; then
    cp -rn "${NOBLE_ROOT}/usr/lib/aarch64-linux-gnu/girepository-1.0"/* "${ROOTFS_DIR}/usr/lib/aarch64-linux-gnu/girepository-1.0/" 2>/dev/null || true
    cp -rn "${NOBLE_ROOT}/usr/lib/aarch64-linux-gnu/girepository-1.0"/* "${ROOTFS_DIR}/usr/lib/girepository-1.0/" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# Suite de Overclock (NVPModel) y Control de Rendimiento de Nintendo Switch
# ------------------------------------------------------------------------------
echo "  -> Configurando suite de Overclock y NVPModel Indicator..."
mkdir -p "${ROOTFS_DIR}/usr/share/nvpmodel_indicator" "${ROOTFS_DIR}/var/lib/nvpmodel" "${ROOTFS_DIR}/usr/share/polkit-1/actions"

if [ -d "${NOBLE_ROOT}/usr/share/nvpmodel_indicator" ]; then
    cp -rn "${NOBLE_ROOT}/usr/share/nvpmodel_indicator"/* "${ROOTFS_DIR}/usr/share/nvpmodel_indicator/" 2>/dev/null || true
fi
if [ -f "${NOBLE_ROOT}/usr/share/polkit-1/actions/com.nvidia.pkexec.nvpmodel.policy" ]; then
    cp -f "${NOBLE_ROOT}/usr/share/polkit-1/actions/com.nvidia.pkexec.nvpmodel.policy" "${ROOTFS_DIR}/usr/share/polkit-1/actions/" 2>/dev/null || true
fi

# Compatibilidad con AyatanaAppIndicator3 y corrección de sintaxis en Python 3.12+
if [ -f "${ROOTFS_DIR}/usr/share/nvpmodel_indicator/nvpmodel_indicator.py" ]; then
    sed -i "s/gi.require_version('AppIndicator3', '0.1')/try:\n    gi.require_version('AppIndicator3', '0.1')\n    from gi.repository import AppIndicator3 as appindicator\nexcept Exception:\n    gi.require_version('AyatanaAppIndicator3', '0.1')\n    from gi.repository import AyatanaAppIndicator3 as appindicator/" "${ROOTFS_DIR}/usr/share/nvpmodel_indicator/nvpmodel_indicator.py" 2>/dev/null || true
    sed -i "/from gi.repository import AppIndicator3 as appindicator/d" "${ROOTFS_DIR}/usr/share/nvpmodel_indicator/nvpmodel_indicator.py" 2>/dev/null || true
    sed -i "s/no is not 0:/no != 0:/g" "${ROOTFS_DIR}/usr/share/nvpmodel_indicator/nvpmodel_indicator.py" 2>/dev/null || true
    sed -i "s/no is 100:/no == 100:/g" "${ROOTFS_DIR}/usr/share/nvpmodel_indicator/nvpmodel_indicator.py" 2>/dev/null || true
    sed -i 's/re.compile("(\\d+)")/re.compile(r"(\\d+)")/g' "${ROOTFS_DIR}/usr/share/nvpmodel_indicator/nvpmodel_indicator.py" 2>/dev/null || true
    chmod 755 "${ROOTFS_DIR}/usr/share/nvpmodel_indicator/nvpmodel_indicator.py"
fi
[ -f "${ROOTFS_DIR}/usr/share/nvpmodel_indicator/nvpmodel_helper.sh" ] && chmod 755 "${ROOTFS_DIR}/usr/share/nvpmodel_indicator/nvpmodel_helper.sh"

# Pre-enlace de nvpmodel.conf
[ -f "${ROOTFS_DIR}/etc/nvpmodel/nvpmodel_t210b01.conf" ] && ln -sf /etc/nvpmodel/nvpmodel_t210b01.conf "${ROOTFS_DIR}/etc/nvpmodel.conf"

# Lanzadores de Overclock
mkdir -p "${ROOTFS_DIR}/etc/xdg/autostart" "${ROOTFS_DIR}/usr/share/applications" "${ROOTFS_DIR}/home/switch/Desktop"
cat << 'EOF' > "${ROOTFS_DIR}/etc/xdg/autostart/nvpmodel_indicator.desktop"
[Desktop Entry]
Name=NVIDIA nvpmodel indicator
GenericName=Overclock & Power Profiles
Comment=Indicator for power profiles and overclock
Exec=/usr/share/nvpmodel_indicator/nvpmodel_indicator.py
Icon=/usr/share/nvpmodel_indicator/nvpmodel-switch.svg
Terminal=false
Type=Application
EOF

cat << 'EOF' > "${ROOTFS_DIR}/usr/share/applications/nvpmodel_indicator.desktop"
[Desktop Entry]
Name=Overclock y Rendimiento (NVPModel)
GenericName=Overclock & Power Profiles
Comment=Configurar perfiles de Overclock, ventilador y energía para Nintendo Switch
Exec=/usr/share/nvpmodel_indicator/nvpmodel_indicator.py
Icon=/usr/share/nvpmodel_indicator/nvpmodel-switch.svg
Terminal=false
Type=Application
Categories=Settings;System;HardwareSettings;
Keywords=overclock;oc;power;fan;performance;
EOF

chmod 755 "${ROOTFS_DIR}/usr/share/applications/nvpmodel_indicator.desktop"
chmod 755 "${ROOTFS_DIR}/etc/xdg/autostart/nvpmodel_indicator.desktop"

# Habilitar servicio de sistema nvpmodel
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf ../nvpmodel.service "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nvpmodel.service" 2>/dev/null || true

# Configuración de bibliotecas Tegra y Dynamic Linker
ln -sf aarch64-linux-gnu/tegra "${ROOTFS_DIR}/usr/lib/tegra" 2>/dev/null || true
cat << 'EOF' > "${ROOTFS_DIR}/etc/ld.so.conf.d/nvidia-tegra.conf"
/usr/lib/aarch64-linux-gnu/tegra
/usr/lib/tegra
EOF

# Sincronización de Xorg 1.20 (ABI 24.1) compatible con el driver binario NVIDIA Tegra
if [ -d "${NOBLE_ROOT}/usr/lib/xorg" ]; then
    echo "  -> Sincronizando servidor Xorg 1.20 (ABI 24.1) compatible con NVIDIA Tegra..."
    cp -a "${NOBLE_ROOT}/usr/lib/xorg" "${ROOTFS_DIR}/usr/lib/"
    cp -a "${NOBLE_ROOT}/usr/bin/Xorg" "${ROOTFS_DIR}/usr/bin/" 2>/dev/null || true
    cp -a "${NOBLE_ROOT}/usr/bin/cvt" "${ROOTFS_DIR}/usr/bin/" 2>/dev/null || true
    cp -a "${NOBLE_ROOT}/usr/bin/gtf" "${ROOTFS_DIR}/usr/bin/" 2>/dev/null || true
    chmod 4755 "${ROOTFS_DIR}/usr/lib/xorg/Xorg" 2>/dev/null || true
    chmod 4755 "${ROOTFS_DIR}/usr/lib/xorg/Xorg.wrap" 2>/dev/null || true

    mkdir -p "${ROOTFS_DIR}/etc/apt/preferences.d"
    cat << 'EOF' > "${ROOTFS_DIR}/etc/apt/preferences.d/00-switch-xorg-restrictions"
Package: xserver-xorg-core
Pin: release *
Pin-Priority: -1

Package: xserver-xorg-video-*
Pin: release *
Pin-Priority: -1

Package: xserver-xorg-input-libinput
Pin: release *
Pin-Priority: -1
EOF
fi

rm -f "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/nvwifibt.service"
rm -f "${ROOTFS_DIR}/etc/systemd/system/nvwifibt.service"
rm -f "${ROOTFS_DIR}/etc/udev/rules.d/99-nv-wifibt.rules"
mkdir -p "${ROOTFS_DIR}/etc/systemd/system"
ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/nvwifibt.service"

# Módulos Bluetooth cargados en boot
mkdir -p "${ROOTFS_DIR}/etc/modules-load.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/modules-load.d/bluetooth.conf"
hci_uart
btbcm
bluedroid_pm
joycond
EOF

# Hook de suspensión / despertar para Bluetooth
mkdir -p "${ROOTFS_DIR}/lib/systemd/system-sleep"
cat << 'EOF' > "${ROOTFS_DIR}/lib/systemd/system-sleep/20_bluetooth"
#!/bin/sh
case $1/$2 in
	pre/*)
		systemctl stop bluetooth 2>/dev/null || true
		modprobe -r hci_uart 2>/dev/null || true
		;;
	post/*)
		modprobe hci_uart 2>/dev/null || true
		systemctl start bluetooth 2>/dev/null || true
		;;
esac
exit 0
EOF
chmod 755 "${ROOTFS_DIR}/lib/systemd/system-sleep/20_bluetooth"

# Firmware regulatorio para WiFi (CRDA / cfg80211)
mkdir -p "${ROOTFS_DIR}/lib/firmware" "${ROOTFS_DIR}/usr/lib/firmware"
for base in "${ROOTFS_DIR}/lib/firmware" "${ROOTFS_DIR}/usr/lib/firmware"; do
    if [ -f "${base}/regulatory.db-upstream" ]; then
        ln -sf regulatory.db-upstream "${base}/regulatory.db"
        ln -sf regulatory.db.p7s-upstream "${base}/regulatory.db.p7s"
    elif [ -f "${base}/regulatory.db-debian" ]; then
        ln -sf regulatory.db-debian "${base}/regulatory.db"
        ln -sf regulatory.db.p7s-debian "${base}/regulatory.db.p7s"
    fi
done
if [ -f "${NOBLE_ROOT}/lib/firmware/regulatory.db" ]; then
    cp -f "${NOBLE_ROOT}/lib/firmware/regulatory.db"* "${ROOTFS_DIR}/lib/firmware/" 2>/dev/null || true
    cp -f "${NOBLE_ROOT}/lib/firmware/regulatory.db"* "${ROOTFS_DIR}/usr/lib/firmware/" 2>/dev/null || true
fi
mkdir -p "${ROOTFS_DIR}/etc/default"
echo 'REGDOMAIN=00' > "${ROOTFS_DIR}/etc/default/crda"

# Hostname y Hosts
echo "debian-switch" > "${ROOTFS_DIR}/etc/hostname"

cat << 'EOF' > "${ROOTFS_DIR}/etc/hosts"
127.0.0.1   localhost
127.0.1.1   debian-switch
::1         localhost ip6-loopback
EOF

# fstab (Solo la partición raíz para evitar fallos de local-fs.target)
cat << 'EOF' > "${ROOTFS_DIR}/etc/fstab"
# /etc/fstab: Nintendo Switch Debian 13 Filesystem Mounts
/dev/mmcblk0p2  /               ext4    noatime,commit=60,errors=remount-ro 0      1
EOF

# Configuración de Bluetooth
mkdir -p "${ROOTFS_DIR}/etc/bluetooth"
cat << 'EOF' > "${ROOTFS_DIR}/etc/bluetooth/main.conf"
[General]
Name = Nintendo Switch
FastConnectable = true
MultiProfile = multiple
AutoEnable = true
JustWorksRepairing = always
Privacy = off

[Policy]
AutoEnable = true
ResumeDelay = 2
EOF
chmod 755 "${ROOTFS_DIR}/etc/bluetooth"
chmod 644 "${ROOTFS_DIR}/etc/bluetooth/main.conf"

# Configuración de Red (NetworkManager) y WiFi
mkdir -p "${ROOTFS_DIR}/etc/NetworkManager/conf.d"
touch "${ROOTFS_DIR}/etc/NetworkManager/conf.d/10-globally-managed-devices.conf"
cat << 'EOF' > "${ROOTFS_DIR}/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf"
[connection]
wifi.powersave = 3
EOF
cat << 'EOF' > "${ROOTFS_DIR}/etc/NetworkManager/conf.d/no-mac-addr-change.conf"
[device-31-mac-addr-change]
match-device=driver:brcmfmac,driver:eagle_sdio,driver:wl
wifi.scan-rand-mac-address=no
EOF
cat << 'EOF' > "${ROOTFS_DIR}/etc/NetworkManager/NetworkManager.conf"
[main]
plugins=keyfile
rc-manager=file

[device]
wifi.scan-rand-mac-address=no

[connection]
wifi.powersave=3
EOF

# Preactivar WiFi y Redes en el estado de NetworkManager
mkdir -p "${ROOTFS_DIR}/var/lib/NetworkManager"
cat << 'EOF' > "${ROOTFS_DIR}/var/lib/NetworkManager/NetworkManager.state"
[main]
NetworkingEnabled=true
WirelessEnabled=true
WWANEnabled=true
EOF
chmod 600 "${ROOTFS_DIR}/var/lib/NetworkManager/NetworkManager.state"

# Integrar accesos en el Gestor de Configuración (Panel de Control de XFCE)
sed -i 's/^Categories=.*/Categories=GNOME;GTK;Settings;HardwareSettings;X-XFCE-SettingsDialog;X-XFCE;X-GNOME-NetworkSettings;X-GNOME-Utilities;/' "${ROOTFS_DIR}/usr/share/applications/nm-connection-editor.desktop" 2>/dev/null || true
sed -i 's/^Categories=.*/Categories=GTK;GNOME;Settings;HardwareSettings;X-XFCE-SettingsDialog;X-XFCE;/' "${ROOTFS_DIR}/usr/share/applications/blueman-manager.desktop" 2>/dev/null || true

# Reglas Polkit para que el usuario switch administre WiFi, Bluetooth y energía sin contraseñas
mkdir -p "${ROOTFS_DIR}/etc/polkit-1/rules.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/polkit-1/rules.d/50-switch-permissions.rules"
polkit.addRule(function(action, subject) {
    if ((action.id.indexOf("org.freedesktop.NetworkManager.") === 0 ||
         action.id.indexOf("org.blueman.") === 0 ||
         action.id.indexOf("org.freedesktop.login1.") === 0 ||
         action.id.indexOf("org.freedesktop.upower.") === 0 ||
         action.id.indexOf("org.freedesktop.udisks2.") === 0) &&
        (subject.isInGroup("sudo") || subject.isInGroup("netdev") || subject.isInGroup("bluetooth") || subject.user === "switch")) {
        return polkit.Result.YES;
    }
});
EOF

mkdir -p "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf /lib/systemd/system/NetworkManager.service "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
ln -sf /lib/systemd/system/bluetooth.service "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/bluetooth.service" 2>/dev/null || true

# Configuración de Hora Automática (NTP con systemd-timesyncd)
mkdir -p "${ROOTFS_DIR}/etc/systemd"
cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/timesyncd.conf"
[Time]
NTP=pool.ntp.org time.cloudflare.com time.google.com
FallbackNTP=0.debian.pool.ntp.org 1.debian.pool.ntp.org
EOF

mkdir -p "${ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants"
ln -sf /lib/systemd/system/systemd-timesyncd.service "${ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service"

# Repositorios oficiales de Debian 13 (Trixie)
cat << 'EOF' > "${ROOTFS_DIR}/etc/apt/sources.list"
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
EOF

# Configuración DNS
rm -f "${ROOTFS_DIR}/etc/resolv.conf"
cat << 'EOF' > "${ROOTFS_DIR}/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Hook de Suspensión y Despertar de Pantalla / Backlight / Audio
mkdir -p "${ROOTFS_DIR}/lib/systemd/system-sleep"
cat << 'EOF' > "${ROOTFS_DIR}/lib/systemd/system-sleep/switch-sleep.sh"
#!/bin/sh
# Nintendo Switch Systemd Suspend/Resume Hook for Debian
# Handles clean audio muting before sleep and backlight/display resync upon resume

case "$1" in
    pre)
        # Silenciar audio antes de suspender para evitar chasquidos
        amixer -c Tegra set 'Speaker Playback Switch' off >/dev/null 2>&1 || true
        amixer -c Tegra set 'HP Playback Switch' off >/dev/null 2>&1 || true
        ;;
    post)
        # 1. Descongelar y reactivar el Framebuffer y backlight
        for fb in /sys/class/graphics/fb*; do
            [ -f "$fb/blank" ] && echo 0 > "$fb/blank" 2>/dev/null || true
        done

        for bl in /sys/class/backlight/*; do
            if [ -f "$bl/brightness" ]; then
                cur=$(cat "$bl/brightness" 2>/dev/null || echo 0)
                max=$(cat "$bl/max_brightness" 2>/dev/null || echo 255)
                if [ "$cur" -eq 0 ]; then
                    echo "$((max / 2))" > "$bl/brightness" 2>/dev/null || true
                else
                    echo "$cur" > "$bl/brightness" 2>/dev/null || true
                fi
            fi
        done

        # 2. Forzar reactivación DPMS en X11 y refresco de pantalla
        for auth in /home/*/.Xauthority /root/.Xauthority; do
            if [ -f "$auth" ]; then
                export DISPLAY=:0
                export XAUTHORITY="$auth"
                xset dpms force on 2>/dev/null || true
                xrefresh 2>/dev/null || true
            fi
        done

        # 3. Restaurar audio y refrescar dispositivos de entrada
        amixer -c Tegra set 'Speaker Playback Switch' on >/dev/null 2>&1 || true
        udevadm trigger --subsystem-match=input 2>/dev/null || true
        ;;
esac
exit 0
EOF
chmod 755 "${ROOTFS_DIR}/lib/systemd/system-sleep/switch-sleep.sh"

# Módulos a cargar en el arranque
cat << 'EOF' > "${ROOTFS_DIR}/etc/modules"
hid-nintendo
uinput
joycond
brcmfmac
nvgpu
EOF

# Configuración ZRAM (2GB de swap comprimido con zstd)
mkdir -p "${ROOTFS_DIR}/etc/default"
cat << 'EOF' > "${ROOTFS_DIR}/etc/default/zramswap"
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF

# ------------------------------------------------------------------------------
# PASO 5: Preparación de la Estructura de Arranque para Hekate (FAT32)
# ------------------------------------------------------------------------------
echo "[*] Paso 5: Generando estructura de arranque FAT32 para Hekate (L4T Bootstack)..."
rm -rf "${BOOT_DIR}"
mkdir -p "${BOOT_DIR}/bootloader/ini" "${BOOT_DIR}/bootloader/res" "${BOOT_DIR}/switchroot/debian"

# 1. Extraer archivos oficiales del bootloader Hekate y firmwares L4T (sys/l4t/*)
if [ ! -f "${DOWNLOADS_DIR}/hekate_release.zip" ]; then
    echo "  -> Descargando última release de Hekate (CTCaer)..."
    HEKATE_URL=$(curl -sL https://api.github.com/repos/CTCaer/hekate/releases/latest | grep "browser_download_url.*hekate_ctcaer.*\.zip" | head -n 1 | cut -d '"' -f 4 || true)
    if [ -n "${HEKATE_URL}" ]; then
        curl -sL -o "${DOWNLOADS_DIR}/hekate_release.zip" "${HEKATE_URL}"
    fi
fi

if [ -f "${DOWNLOADS_DIR}/hekate_release.zip" ]; then
    echo "  -> Extrayendo Hekate y firmwares SC7/BPMP en bootloader/..."
    7z x -y "${DOWNLOADS_DIR}/hekate_release.zip" -o"${BOOT_DIR}" > /dev/null
fi

# 2. Configurar bootstack L4T (bl31.bin, bl33.bin, boot.scr, initramfs)
echo "  -> Configurando bootstack L4T (bl31, bl33, boot.scr, initramfs)..."
BSP_BOOTSTACK="${ROOTFS_DIR}/opt/switchroot/bootstack"

if [ -d "${BSP_BOOTSTACK}" ]; then
    cp "${BSP_BOOTSTACK}/bl31.bin" "${BOOT_DIR}/switchroot/debian/bl31.bin"
    cp "${BSP_BOOTSTACK}/bl33.bin" "${BOOT_DIR}/switchroot/debian/bl33.bin"
    cp "${BSP_BOOTSTACK}/initramfs" "${BOOT_DIR}/switchroot/debian/initramfs"
fi

if [ -f "${DOWNLOADS_DIR}/switch-assets/bootlogo_debian.bmp" ]; then
    cp "${DOWNLOADS_DIR}/switch-assets/bootlogo_debian.bmp" "${BOOT_DIR}/switchroot/debian/bootlogo_debian.bmp"
elif [ -f "${BSP_BOOTSTACK}/bootlogo_ubuntu.bmp" ]; then
    cp "${BSP_BOOTSTACK}/bootlogo_ubuntu.bmp" "${BOOT_DIR}/switchroot/debian/bootlogo_debian.bmp"
fi

if [ -f "${DOWNLOADS_DIR}/switch-assets/icon_debian.bmp" ]; then
    cp "${DOWNLOADS_DIR}/switch-assets/icon_debian.bmp" "${BOOT_DIR}/switchroot/debian/icon_debian.bmp"
elif [ -f "${BSP_BOOTSTACK}/icon_ubuntu_hue.bmp" ]; then
    cp "${BSP_BOOTSTACK}/icon_ubuntu_hue.bmp" "${BOOT_DIR}/switchroot/debian/icon_debian.bmp"
fi

MKIMAGE_BIN="$(command -v mkimage || echo "${TOOLS_DIR}/usr/bin/mkimage")"

# Modificar boot.scr para agregar net.ifnames=0 (manteniendo nombre wlan0)
if [ -f "${BSP_BOOTSTACK}/boot.scr" ]; then
    tail -c +73 "${BSP_BOOTSTACK}/boot.scr" > "${WORKDIR}/boot.txt"
    sed -i 's/systemd.legacy_systemd_cgroup_controller=1/systemd.legacy_systemd_cgroup_controller=1 net.ifnames=0/' "${WORKDIR}/boot.txt"
    "${MKIMAGE_BIN}" -A arm64 -T script -C none -n "boot.scr" -d "${WORKDIR}/boot.txt" "${BOOT_DIR}/switchroot/debian/boot.scr"
    rm -f "${WORKDIR}/boot.txt"
fi

# 3. Kernel compilado uImage
echo "  -> Generando uImage del kernel recién compilado y parchado..."
"${MKIMAGE_BIN}" -A arm64 -O linux -T kernel -C gzip -a 0x80200000 -e 0x80200000 -n Switch-Debian-13 \
    -d "${KERNEL_DIR}/arch/arm64/boot/Image.gz" "${BOOT_DIR}/switchroot/debian/uImage"

# 4. Tabla de Device Trees compilada (nx-plat.dtimg) para Switch V1, V2, Lite y OLED
echo "  -> Generando nx-plat.dtimg para Switch V1, V2, Lite y OLED..."
python3 "${TOOLS_DIR}/mkdtboimg.py" create "${BOOT_DIR}/switchroot/debian/nx-plat.dtimg" --page_size=1000 \
    "${KERNEL_DIR}/arch/arm64/boot/dts/tegra210-odin.dtb" --id=0x4F44494E \
    "${KERNEL_DIR}/arch/arm64/boot/dts/tegra210b01-odin.dtb" --id=0x4F44494E --rev=0xb01 \
    "${KERNEL_DIR}/arch/arm64/boot/dts/tegra210b01-vali.dtb" --id=0x56414C49 \
    "${KERNEL_DIR}/arch/arm64/boot/dts/tegra210b01-fric.dtb" --id=0x46524947

if [ -f "${ROOTFS_DIR}/opt/switchroot/modules.tar.gz" ]; then
    echo "  -> Extrayendo firmware oficial en RootFS..."
    TAR_MOD_TMP="${WORKDIR}/tar_mod_tmp"
    rm -rf "${TAR_MOD_TMP}"
    mkdir -p "${TAR_MOD_TMP}"
    tar -xzpf "${ROOTFS_DIR}/opt/switchroot/modules.tar.gz" -C "${TAR_MOD_TMP}"
    
    mkdir -p "${ROOTFS_DIR}/usr/lib/firmware" "${ROOTFS_DIR}/lib/firmware"
    if [ -d "${TAR_MOD_TMP}/firmware" ]; then
        cp -rn "${TAR_MOD_TMP}/firmware"/* "${ROOTFS_DIR}/usr/lib/firmware/" 2>/dev/null || true
        cp -rn "${TAR_MOD_TMP}/firmware"/* "${ROOTFS_DIR}/lib/firmware/" 2>/dev/null || true
    fi
    rm -rf "${TAR_MOD_TMP}"
fi

# Duplicar directorios de módulos para compatibilidad con usrmerge y nombres con/sin '+'
mkdir -p "${ROOTFS_DIR}/usr/lib/modules" "${ROOTFS_DIR}/lib/modules"
for mdir in "${ROOTFS_DIR}/lib/modules"/* "${ROOTFS_DIR}/usr/lib/modules"/*; do
    if [ -d "$mdir" ] && [ ! -L "$mdir" ] && [[ "$(basename "$mdir")" == *"4.9.140-l4t"* ]]; then
        mname="$(basename "$mdir")"
        cp -rn "${ROOTFS_DIR}/lib/modules/${mname}" "${ROOTFS_DIR}/usr/lib/modules/" 2>/dev/null || true
        cp -rn "${ROOTFS_DIR}/usr/lib/modules/${mname}" "${ROOTFS_DIR}/lib/modules/" 2>/dev/null || true
        [ ! -e "${ROOTFS_DIR}/lib/modules/4.9.140-l4t" ] && ln -sf "${mname}" "${ROOTFS_DIR}/lib/modules/4.9.140-l4t" 2>/dev/null || true
        [ ! -e "${ROOTFS_DIR}/usr/lib/modules/4.9.140-l4t" ] && ln -sf "${mname}" "${ROOTFS_DIR}/usr/lib/modules/4.9.140-l4t" 2>/dev/null || true
        /sbin/depmod -a -b "${ROOTFS_DIR}" "${mname}" 2>/dev/null || depmod -a -b "${ROOTFS_DIR}" "${mname}" 2>/dev/null || true
    fi
done

for bdir in "${ROOTFS_DIR}/usr/lib/firmware/brcm" "${ROOTFS_DIR}/lib/firmware/brcm"; do
    if [ -d "$bdir" ]; then
        ln -sf brcmfmac4356A3-pcie.bin "$bdir/brcmfmac4356-pcie.bin" 2>/dev/null || true
        ln -sf brcmfmac4356A3-pcie.txt "$bdir/brcmfmac4356-pcie.txt" 2>/dev/null || true
        for fw in brcmfmac4356-pcie.nintendo,switch.txt brcmfmac4356-pcie.nintendo,odin.txt brcmfmac4356-pcie.nintendo,vali.txt brcmfmac4356-pcie.nintendo,fric.txt; do
            cp -f "$bdir/brcmfmac4356A3-pcie.txt" "$bdir/$fw" 2>/dev/null || true
        done
        ln -sf BCM4356A3.hcd "$bdir/bcm4356.hcd" 2>/dev/null || true
    fi
done

# 5. Generar archivo de configuración debian.ini compatible con el motor L4T de Hekate
cat << 'EOF' > "${BOOT_DIR}/bootloader/ini/debian.ini"
[Debian 13 Trixie]
l4t=1
boot_prefixes=/switchroot/debian/
id=SWR-DEB
r2p_action=self
fbconsole=0
icon=switchroot/debian/icon_debian.bmp
logopath=switchroot/debian/bootlogo_debian.bmp
EOF

# ------------------------------------------------------------------------------
# PASO 6: Empaquetado y Generación de Checksums SHA256
# ------------------------------------------------------------------------------
echo "[*] Paso 6: Empaquetando la Release de Debian 13 Trixie para Nintendo Switch..."

DESKTOP_ENV="${DESKTOP_ENV:-xfce4}"
RELEASE_FAT32="${WORKDIR}/switch-debian-13-trixie-${DESKTOP_ENV}-fat32.zip"
RELEASE_ROOTFS="${WORKDIR}/switch-debian-13-trixie-${DESKTOP_ENV}-rootfs.tar.gz"

echo "  -> Creando ${RELEASE_FAT32}..."
(cd "${BOOT_DIR}" && 7z a -tzip "${RELEASE_FAT32}" ./*) > /dev/null

echo "  -> Creando ${RELEASE_ROOTFS} con propietario root (UID 0: GID 0) y SUID preservados..."

echo "  -> Normalizando propietarios (root:root / UID 0: GID 0) en RootFS..."
chown -R 0:0 "${ROOTFS_DIR}" 2>/dev/null || true
if [ -d "${ROOTFS_DIR}/home/switch" ]; then
    chown -R 1000:1000 "${ROOTFS_DIR}/home/switch" 2>/dev/null || true
fi

# 1. Asegurar SUID y permisos en binarios clave en el árbol
chown 0:0 "${ROOTFS_DIR}/etc/sudoers" "${ROOTFS_DIR}/etc/sudo.conf" 2>/dev/null || true
chown -R 0:0 "${ROOTFS_DIR}/etc/sudoers.d" 2>/dev/null || true
chmod 0440 "${ROOTFS_DIR}/etc/sudoers" 2>/dev/null || true
chmod 0440 "${ROOTFS_DIR}/etc/sudoers.d"/* 2>/dev/null || true
[ -f "${ROOTFS_DIR}/etc/sudo.conf" ] && chmod 0644 "${ROOTFS_DIR}/etc/sudo.conf" 2>/dev/null || true

for suid_bin in \
    "${ROOTFS_DIR}/usr/bin/sudo" \
    "${ROOTFS_DIR}/usr/bin/su" \
    "${ROOTFS_DIR}/usr/bin/passwd" \
    "${ROOTFS_DIR}/usr/bin/gpasswd" \
    "${ROOTFS_DIR}/usr/bin/newgrp" \
    "${ROOTFS_DIR}/usr/bin/chsh" \
    "${ROOTFS_DIR}/usr/bin/chfn" \
    "${ROOTFS_DIR}/usr/bin/crontab" \
    "${ROOTFS_DIR}/usr/lib/xorg/Xorg" \
    "${ROOTFS_DIR}/usr/lib/xorg/Xorg.wrap" \
    "${ROOTFS_DIR}/usr/lib/polkit-1/polkit-agent-helper-1" \
    "${ROOTFS_DIR}/usr/lib/aarch64-linux-gnu/polkit-1/polkit-agent-helper-1"; do
    if [ -f "$suid_bin" ]; then
        chown 0:0 "$suid_bin" 2>/dev/null || true
        chmod 4755 "$suid_bin" 2>/dev/null || true
    fi
done

if [ -f "${ROOTFS_DIR}/usr/lib/dbus-1.0/dbus-daemon-launch-helper" ]; then
    chown 0:0 "${ROOTFS_DIR}/usr/lib/dbus-1.0/dbus-daemon-launch-helper" 2>/dev/null || true
    chmod 4754 "${ROOTFS_DIR}/usr/lib/dbus-1.0/dbus-daemon-launch-helper" 2>/dev/null || true
fi

# 2. Configurar tmpfiles.d para asegurar permisos dinámicos de /home/switch (1000:1000), /tmp (1777), sudoers y lightdm en arranque
mkdir -p "${ROOTFS_DIR}/etc/tmpfiles.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/tmpfiles.d/switch-user.conf"
# Type Path Mode UID GID Age Argument
d /home/switch 0755 switch switch -
Z /home/switch - switch switch -
d /tmp 1777 root root -
d /var/tmp 1777 root root -
d /var/lib/lightdm 0755 lightdm lightdm -
Z /var/lib/lightdm - lightdm lightdm -
d /var/lib/lightdm/data 0750 lightdm lightdm -
z /var/lib/lightdm/data 0750 lightdm lightdm -
d /var/cache/lightdm 0755 lightdm lightdm -
Z /var/cache/lightdm - lightdm lightdm -
d /var/log/lightdm 0755 lightdm root -
Z /var/log/lightdm - lightdm root -
d /run/lightdm 0755 lightdm lightdm -
Z /run/lightdm - lightdm lightdm -
d /var/lib/nvpmodel 0777 root root -
Z /var/lib/nvpmodel - root root -
z /etc/sudoers 0440 root root -
z /etc/sudoers.d 0750 root root -
Z /etc/sudoers.d 0440 root root -
z /etc/sudo.conf 0644 root root -
z /usr/bin/sudo 4755 root root -
z /usr/bin/su 4755 root root -
z /usr/bin/passwd 4755 root root -
z /usr/bin/crontab 4755 root root -
z /usr/lib/polkit-1/polkit-agent-helper-1 4755 root root -
z /usr/lib/aarch64-linux-gnu/polkit-1/polkit-agent-helper-1 4755 root root -
EOF

# 3. Servicio de arranque temprano para garantizar permisos correctos de sudo ante cualquier medio de instalación
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants"
cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/system/switch-fix-perms.service"
[Unit]
Description=Fix RootFS ownership and sudo permissions
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target systemd-tmpfiles-setup.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'chown 0:0 /etc /etc/sudo.conf /etc/sudoers /etc/sudoers.d /etc/sudoers.d/* 2>/dev/null; chmod 0440 /etc/sudoers /etc/sudoers.d/* 2>/dev/null; chmod 0644 /etc/sudo.conf 2>/dev/null; chmod 4755 /usr/bin/sudo /usr/bin/su /usr/bin/passwd /usr/bin/crontab 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF
ln -sf /etc/systemd/system/switch-fix-perms.service "${ROOTFS_DIR}/etc/systemd/system/sysinit.target.wants/switch-fix-perms.service"

# 4. Empaquetar forzando UID 0: GID 0 (root:root) en todos los encabezados tar
(cd "${ROOTFS_DIR}" && tar --numeric-owner --owner=0 --group=0 -czf "${RELEASE_ROOTFS}" ./)

echo "  -> Generando checksums SHA256..."
(cd "${WORKDIR}" && sha256sum switch-debian-13-trixie-${DESKTOP_ENV}-* > SHA256SUMS.txt)

echo "========================================================================"
echo "  CONSTRUCCIÓN EXITOSA DE DEBIAN 13 (TRIXIE) PARA NINTENDO SWITCH!"
echo "========================================================================"
echo "Archivos generados en ${WORKDIR}:"
ls -lh "${WORKDIR}"/*.zip "${WORKDIR}"/*.tar.gz "${WORKDIR}"/SHA256SUMS.txt

