#!/usr/bin/env python3
#
# Copyright (c) 2019, NVIDIA CORPORATION.  All Rights Reserved.
# Copyright (c) 2021, CTCaer.  All Rights Reserved.
#
# NVIDIA CORPORATION and its licensors retain all intellectual property
# and proprietary rights in and to this software, related documentation
# and any modifications thereto.  Any use, reproduction, disclosure or
# distribution of this software and related documentation without an express
# license agreement from NVIDIA CORPORATION is strictly prohibited.
#

import os
import signal
import gi
import nvpmodel as nvpm
import subprocess
import time
import threading
import re
import sys
import glob

gi.require_version("Gtk", "3.0")
try:
    gi.require_version('AppIndicator3', '0.1')
    from gi.repository import AppIndicator3 as appindicator
except Exception:
    gi.require_version('AyatanaAppIndicator3', '0.1')
    from gi.repository import AyatanaAppIndicator3 as appindicator

from gi.repository import Gtk as gtk
from gi.repository import GdkPixbuf as gdkpixbuf
from gi.repository import GObject

INDICATOR_ID = 'nvpmodel'
INDICATORAPPS_ID = 'nvpmodel_apps'

if os.path.exists('/usr/share/nvpmodel_indicator/nvpmodel-switch.svg'):
    ICON_DEFAULT = os.path.abspath('/usr/share/nvpmodel_indicator/nvpmodel-switch.svg')
else:
    ICON_DEFAULT = os.path.abspath('/usr/share/nvpmodel_indicator/nv_logo.svg')

if os.path.exists('/usr/share/nvpmodel_indicator/nvpmodel-profiles.svg'):
    ICON_SHADOW = os.path.abspath('/usr/share/nvpmodel_indicator/nvpmodel-profiles.svg')
else:
    ICON_SHADOW = os.path.abspath('/usr/share/nvpmodel_indicator/nvpmodel-switch.svg')

JOYCON_MAP = os.path.abspath('/usr/share/nvpmodel_indicator/jc_map.png')

nvpmodel_helper_path = "/usr/share/nvpmodel_indicator/nvpmodel_helper.sh"

GET_COLOR_MODE = '1'
SET_COLOR_MODE = '2'
GET_COLOR_MODE_EN = '3'
GET_AUTO_PROFILES = '4'
SET_AUTO_PROFILES = '5'
GET_CHG_LIMIT_EN = '8'
GET_CHG_LIMIT_SAVED = '9'

auto_profiles = False
charging_limits = False
color_modes = False

_last_known_temp = None

def get_thermal_stats(cur_fan="0"):
    global _last_known_temp
    temp = None

    tz_paths = sorted(
        glob.glob("/sys/class/thermal/thermal_zone*"),
        key=lambda x: int(x.split("thermal_zone")[-1]) if x.split("thermal_zone")[-1].isdigit() else 99
    )

    # 1. Look for CPU / SoC thermal zone first
    for tz_dir in tz_paths:
        tz_type_f = os.path.join(tz_dir, "type")
        tz_temp_f = os.path.join(tz_dir, "temp")
        if os.path.isfile(tz_type_f) and os.path.isfile(tz_temp_f):
            try:
                with open(tz_type_f, "r") as f:
                    tz_type = f.read().strip().lower()
                if any(x in tz_type for x in ["cpu", "pll", "tdiode", "soc", "tegra"]):
                    with open(tz_temp_f, "r") as f:
                        raw = int(f.read().strip())
                        if 0 < raw < 125000:
                            temp = round(raw / 1000.0)
                            break
            except Exception:
                pass

    # 2. Fallback: check any thermal zone reporting valid millidegrees (10C to 110C)
    if temp is None:
        for tz_dir in tz_paths:
            tz_temp_f = os.path.join(tz_dir, "temp")
            if os.path.isfile(tz_temp_f):
                try:
                    with open(tz_temp_f, "r") as f:
                        raw = int(f.read().strip())
                        if 10000 <= raw <= 115000:
                            temp = round(raw / 1000.0)
                            break
                except Exception:
                    pass

    # 3. Fallback to last known temperature if sensor was momentarily unreadable
    if temp is not None:
        _last_known_temp = temp
    else:
        temp = _last_known_temp

    # Fan & RPM
    fan_dirs = [
        "/sys/devices/pwm-fan",
        "/sys/bus/platform/devices/pwm-fan",
    ]

    target_pwm_pct_map = {"1": 30, "0": 50, "2": 75, "3": 100}
    fallback_pwm = target_pwm_pct_map.get(str(cur_fan), 50)
    pwm = None
    rpm = None

    for fd in fan_dirs:
        if os.path.isdir(fd):
            # Ensure tachometer is enabled if not already
            tach_file = os.path.join(fd, "tach_enable")
            if os.path.isfile(tach_file):
                try:
                    with open(tach_file, "r+") as f:
                        if f.read().strip() == "0":
                            f.seek(0)
                            f.write("1\n")
                except Exception:
                    pass

            # Read measured RPM
            rpm_file = os.path.join(fd, "rpm_measured")
            if os.path.isfile(rpm_file):
                try:
                    with open(rpm_file, "r") as f:
                        v = int(f.read().strip())
                        rpm = v
                except Exception:
                    pass

            # Read current PWM duty
            for pf in ["cur_pwm", "target_pwm"]:
                pwm_file = os.path.join(fd, pf)
                if os.path.isfile(pwm_file):
                    try:
                        with open(pwm_file, "r") as f:
                            pwm_val = int(f.read().strip())
                            pwm = min(100, max(0, round(pwm_val * 100 / 255.0)))
                            break
                    except Exception:
                        pass
            break

    if pwm is None:
        pwm = fallback_pwm

    if rpm is not None and rpm > 0:
        fan_info = f"{pwm}% ({rpm} RPM)"
    elif rpm is not None:
        fan_info = f"{pwm}% (0 RPM)"
    else:
        fan_info = f"{pwm}%"

    return temp, fan_info

def get_custom_fan_mode():
    try:
        if os.path.exists("/var/lib/nvpmodel/custom_fan_mode"):
            with open("/var/lib/nvpmodel/custom_fan_mode", "r") as f:
                v = f.read().strip()
                if v:
                    return v
    except Exception:
        pass
    return fm.cur_mode() or "0"

updating_menu = False

def update_indicator_label(force_fmode=None):
    cur_pwr = pm.cur_mode()
    cur_fan = force_fmode if force_fmode is not None else get_custom_fan_mode()
    temp_val, fan_str = get_thermal_stats(cur_fan)

    pwr_name = pm.get_name_by_id(cur_pwr) or "Console"
    label_parts = [pwr_name]
    if temp_val is not None:
        label_parts.append(f"{temp_val}°C")
    else:
        label_parts.append("--°C")
    label_parts.append(f"Fan: {fan_str}")

    final_label = " | ".join(label_parts) + "  "

    def _apply_ui():
        try:
            indicator.set_label(final_label, final_label)
        except Exception:
            pass
        try:
            indicator.set_title(final_label)
        except Exception:
            pass
        try:
            indicatorApps.set_title(f"Switch: {final_label}")
        except Exception:
            pass
    GObject.idle_add(_apply_ui, priority=GObject.PRIORITY_DEFAULT)

def confirm_reboot():
    dialog = gtk.MessageDialog(None, 0, gtk.MessageType.WARNING,
        gtk.ButtonsType.OK_CANCEL, "System reboot is required to apply changes")
    dialog.set_title("WARNING")
    dialog.format_secondary_text( "Do you want to reboot NOW?")
    response = dialog.run()
    dialog.destroy()
    return response == gtk.ResponseType.OK

def set_power_mode(item, mode_id):
    global updating_menu
    if updating_menu:
        return
    if item.get_active() and mode_id != pm.cur_mode():
        success = pm.set_mode(mode_id, ['pkexec'])
        if not success and confirm_reboot():
            pm.set_mode(mode_id, ['pkexec'], force=True)
            return
        update_indicator_label()

def set_fan_mode(item, mode_id):
    global updating_menu
    if updating_menu:
        return
    if item.get_active():
        mode_str = str(mode_id)
        target_pwm_map = {"1": 77, "0": 128, "2": 192, "3": 255}
        desired_pwm = target_pwm_map.get(mode_str, 128)

        # 1. Direct immediate write to sysfs if writable (zero delay!)
        for p in ["/sys/devices/pwm-fan", "/sys/bus/platform/devices/pwm-fan"]:
            if os.path.isdir(p):
                try:
                    with open(os.path.join(p, "temp_control"), "w") as f:
                        f.write("0\n")
                    with open(os.path.join(p, "pwm_cap"), "w") as f:
                        f.write("255\n")
                    with open(os.path.join(p, "state_cap"), "w") as f:
                        f.write("9\n")
                    with open(os.path.join(p, "target_pwm"), "w") as f:
                        f.write(f"{desired_pwm}\n")
                except Exception:
                    pass
                break

        # 2. Save mode to custom_fan_mode file directly
        try:
            with open("/var/lib/nvpmodel/custom_fan_mode", "w") as f:
                f.write(f"{mode_str}\n")
        except Exception:
            pass

        # 3. Also trigger helper via pkexec in background thread to guarantee persistence and profile
        def _run_helper():
            subprocess.call(['pkexec', nvpmodel_helper_path, '10', mode_str])
        threading.Thread(target=_run_helper, daemon=True).start()

        # 4. Immediately update UI label
        update_indicator_label(force_fmode=mode_str)


def set_chg_mode(item, mode_id):
    if item.get_active() and mode_id != cm.cur_mode():
        if mode_id != "0":
            dialog = gtk.MessageDialog(None, 0, gtk.MessageType.WARNING, gtk.ButtonsType.OK,
                "Battery charging limit protection")
            dialog.set_title("WARNING")
            dialog.format_secondary_text( "This protects battery against prolonged high voltage which decreases capacity life!\n\nIt also disables charging at sleep!\n\n(The protection does not continue outside of L4T)")
            dialog.run()
            dialog.destroy()
        success = cm.set_mode(mode_id, ['pkexec'])
        if not success and confirm_reboot():
            cm.set_mode(mode_id, ['pkexec'], force=True)
            return

def set_cm_mode(item, mode_id):
    cur_mode = subprocess.call([nvpmodel_helper_path, GET_COLOR_MODE])
    if item.get_active() and mode_id != cur_mode:
        if cur_mode == 5 and mode_id >= 5:
            return
        if mode_id == 5:
            if cur_mode == 0:
                cur_mode = 4
            mode_id = cur_mode + 4;
        subprocess.call([nvpmodel_helper_path, SET_COLOR_MODE, str(mode_id)])

def do_tegrastats(_):
    cmd = "x-terminal-emulator -e pkexec tegrastats-l4t".split()
    subprocess.Popen(cmd)

def do_r2c(_):
    cmd = "pkexec r2c".split()
    subprocess.call(cmd)

def jc_map_resize(win, req):
    alloc = win.get_allocation()
    win.disconnect(win.connection_id)
    pixbuf = gdkpixbuf.Pixbuf.new_from_file(JOYCON_MAP)
    if alloc.width < 1280 and alloc.height < 720 and alloc.width != 200:
        pixbuf = pixbuf.scale_simple(alloc.width, alloc.height, gdkpixbuf.InterpType.BILINEAR)
    image = gtk.Image.new_from_pixbuf(pixbuf)
    image.show()
    win.add(image)
    win.set_title("Joy-Con Mapping")
    if alloc.width < 1280 and alloc.height < 720:
        win.maximize()
    else:
        win.unmaximize()

def do_jchelp(_):
    window = gtk.Window()
    window.show_all()
    window.connection_id = window.connect('size-allocate', jc_map_resize)
    window.maximize()

def do_auto_profiles(self):
    global auto_profiles
    if auto_profiles == self.get_active():
        return
    auto_profiles = self.get_active()
    if auto_profiles:
        subprocess.call([nvpmodel_helper_path, SET_AUTO_PROFILES, '1'])
    else:
        subprocess.call([nvpmodel_helper_path, SET_AUTO_PROFILES, '0'])

def build_menu():
    global main_menu

    menu = gtk.Menu()
    main_menu = menu

    item_pm = gtk.MenuItem('Power mode:')
    item_pm.set_sensitive(False)
    menu.append(item_pm)

    group = []
    for mode in pm.power_modes():
        label = mode.id + ': ' + mode.name
        item_mode = gtk.RadioMenuItem.new_with_label(group, label)
        group = item_mode.get_group()
        item_mode.connect('activate', set_power_mode, mode.id)
        menu.append(item_mode)

    item_sep = gtk.SeparatorMenuItem()
    menu.append(item_sep)

    item_fm = gtk.MenuItem('Fan mode:')
    item_fm.set_sensitive(False)
    menu.append(item_fm)

    fgroup = []
    for mode in fm.fan_modes():
        label = mode.id + ': ' + mode.name
        item_mode = gtk.RadioMenuItem.new_with_label(fgroup, label)
        fgroup = item_mode.get_group()
        item_mode.connect('activate', set_fan_mode, mode.id)
        menu.append(item_mode)

    # 100% Full Speed mode
    item_full = gtk.RadioMenuItem.new_with_label(fgroup, '3: Full (100%)')
    fgroup = item_full.get_group()
    item_full.connect('activate', set_fan_mode, '3')
    menu.append(item_full)

    item_sep = gtk.SeparatorMenuItem()
    menu.append(item_sep)

    item_set = gtk.MenuItem('Settings:')
    item_set.set_sensitive(False)
    menu.append(item_set)

    item_auto = gtk.CheckMenuItem('Automatic profiles')
    item_auto.connect('toggled', do_auto_profiles)
    menu.append(item_auto)
    auto_profiles = subprocess.call([nvpmodel_helper_path, GET_AUTO_PROFILES])
    if auto_profiles:
        item_auto.set_active(True)

    menu.show_all()
    return menu

def radio_cm_item(menu, cur_mode, grp, lbl, id):
    label = lbl
    item_mode = gtk.RadioMenuItem.new_with_label(grp, label)
    item_mode.connect('activate', set_cm_mode, id)
    if id == cur_mode:
        item_mode.set_active(True)
    menu.append(item_mode)
    cgroup = item_mode.get_group()
    return cgroup

def build_app_menu():
    global main_app_menu

    menu = gtk.Menu()
    main_app_menu = menu

    if charging_limits:
        item_fm = gtk.MenuItem('Charging Limit:')
        item_fm.set_sensitive(False)
        menu.append(item_fm)
        cgroup = []
        for mode in cm.chg_modes():
            no = eval(mode.id)
            if no != 0:
                no += 5
            else:
                no = 100
            label = str(no) + '%: ' + mode.name
            item_mode = gtk.RadioMenuItem.new_with_label(cgroup, label)
            cgroup = item_mode.get_group()
            item_mode.connect('activate', set_chg_mode, mode.id)
            menu.append(item_mode)
        item_sep = gtk.SeparatorMenuItem()
        menu.append(item_sep)

    if color_modes:
        item_cm = gtk.MenuItem('Color Mode:')
        item_cm.set_sensitive(False)
        menu.append(item_cm)
        cur_cm_mode = subprocess.call([nvpmodel_helper_path, GET_COLOR_MODE])
        cgroup = []
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Washed Out', 1)
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Basic', 2)
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Natural', 3)
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Vivid', 4)
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Saturated', 0)
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Night Mode', 5)
        item_sep = gtk.SeparatorMenuItem()
        menu.append(item_sep)

    item_app = gtk.MenuItem('Apps:')
    item_app.set_sensitive(False)
    menu.append(item_app)

    item_tstats = gtk.MenuItem('Tegra Stats')
    item_tstats.connect('activate', do_tegrastats)
    menu.append(item_tstats)

    item_r2c = gtk.MenuItem('Reboot 2 Config')
    item_r2c.connect('activate', do_r2c)
    menu.append(item_r2c)

    item_sep = gtk.SeparatorMenuItem()
    menu.append(item_sep)

    item_jch = gtk.MenuItem('Joy-Con Mapping Help')
    item_jch.connect('activate', do_jchelp)
    menu.append(item_jch)

    menu.show_all()
    return menu

def mode_change_monitor(running):
    global main_menu, updating_menu
    cur_mode = pm.cur_mode()
    cur_fmode = get_custom_fan_mode()
    pmode_changed = False
    fmode_changed = False

    while running.is_set():
        try:
            new_pm = pm.cur_mode()
            new_fm = get_custom_fan_mode()

            if cur_mode != new_pm:
                pmode_changed = True
                cur_mode = new_pm
            if cur_fmode != new_fm:
                fmode_changed = True
                cur_fmode = new_fm

            # Enforce current custom fan mode PWM, with thermal safety guard
            if cur_fmode in ["0", "1", "2", "3"]:
                target_pwm_map = {"1": 77, "0": 128, "2": 192, "3": 255}
                desired_pwm = target_pwm_map.get(cur_fmode, 128)

                # Thermal safety boost: if temperature rises dangerously high, ramp fan up
                temp_val, _ = get_thermal_stats(cur_fmode)
                if temp_val is not None:
                    if temp_val >= 78:
                        desired_pwm = 255
                    elif temp_val >= 68 and desired_pwm < 192:
                        desired_pwm = 192

                for p in ["/sys/devices/pwm-fan", "/sys/bus/platform/devices/pwm-fan"]:
                    if os.path.isdir(p):
                        pwmc = os.path.join(p, "pwm_cap")
                        sc = os.path.join(p, "state_cap")
                        tc = os.path.join(p, "temp_control")
                        tp = os.path.join(p, "target_pwm")
                        if os.path.exists(pwmc):
                            try:
                                with open(pwmc, "r+") as f:
                                    if f.read().strip() != "255":
                                        f.seek(0)
                                        f.write("255\n")
                            except Exception:
                                pass
                        if os.path.exists(sc):
                            try:
                                with open(sc, "r+") as f:
                                    if f.read().strip() != "9":
                                        f.seek(0)
                                        f.write("9\n")
                            except Exception:
                                pass
                        if os.path.exists(tc):
                            try:
                                with open(tc, "r+") as f:
                                    if f.read().strip() != "0":
                                        f.seek(0)
                                        f.write("0\n")
                            except Exception:
                                pass
                        if os.path.exists(tp):
                            try:
                                with open(tp, "r+") as f:
                                    cur_p = f.read().strip()
                                    if cur_p != str(desired_pwm):
                                        f.seek(0)
                                        f.write(f"{desired_pwm}\n")
                            except Exception:
                                pass
                        break

            update_indicator_label()

            # Update active modes in menu if changed
            if pmode_changed or fmode_changed:
                fan_section = False
                for child in main_menu.get_children():
                    lbl = child.get_label()
                    if lbl == 'Fan mode:':
                        fan_section = True
                        continue
                    if lbl == 'Settings:':
                        fan_section = False
                        continue
                    if not fan_section and pmode_changed and lbl and lbl[0] == cur_mode:
                        pmode_changed = False
                        if hasattr(child, 'get_active') and not child.get_active():
                            def _set_pm(c):
                                global updating_menu
                                updating_menu = True
                                c.set_active(True)
                                updating_menu = False
                            GObject.idle_add(_set_pm, child, priority=GObject.PRIORITY_DEFAULT)
                    if fan_section and fmode_changed and lbl and lbl[0] == cur_fmode:
                        fmode_changed = False
                        if hasattr(child, 'get_active') and not child.get_active():
                            def _set_fm(c):
                                global updating_menu
                                updating_menu = True
                                c.set_active(True)
                                updating_menu = False
                            GObject.idle_add(_set_fm, child, priority=GObject.PRIORITY_DEFAULT)
        except Exception:
            pass

        time.sleep(2)

pm = nvpm.nvpmodel()
fm = nvpm.nvfmodel()
cm = nvpm.nvcmodel()
charging_limits = subprocess.call([nvpmodel_helper_path, GET_CHG_LIMIT_EN])
color_modes = subprocess.call([nvpmodel_helper_path, GET_COLOR_MODE_EN])

for mode in pm.power_modes():
    mode.name = mode.name.replace('_', ' ')

for mode in fm.fan_modes():
    mode.name = mode.name.replace('_', ' ')

for mode in cm.chg_modes():
    mode.name = mode.name.replace('_', ' ')

signal.signal(signal.SIGINT, signal.SIG_DFL)

pwr_mode = pm.cur_mode()
fan_mode = get_custom_fan_mode()
chg_mode = str(subprocess.call([nvpmodel_helper_path, GET_CHG_LIMIT_SAVED]))

indicatorApps = appindicator.Indicator.new(INDICATORAPPS_ID, ICON_DEFAULT,
    appindicator.IndicatorCategory.SYSTEM_SERVICES)
indicatorApps.set_status(appindicator.IndicatorStatus.ACTIVE)
main_app_menu = build_app_menu()
indicatorApps.set_menu(main_app_menu)

indicator = appindicator.Indicator.new(INDICATOR_ID, ICON_SHADOW,
    appindicator.IndicatorCategory.SYSTEM_SERVICES)
init_pwr = pm.get_name_by_id(pwr_mode) or "Console"
indicator.set_label(init_pwr + '  ', INDICATOR_ID)
indicator.set_status(appindicator.IndicatorStatus.ACTIVE)
main_menu = build_menu()
indicator.set_menu(main_menu)
update_indicator_label()

# Set active modes in menu
fan_section = False
updating_menu = True
chg_mode_no = eval(chg_mode)
for child in main_menu.get_children():
    label = child.get_label()
    if label == 'Fan mode:':
        fan_section = True
        continue
    if label == 'Settings:':
        fan_section = False
        continue
    if not fan_section and label and label[0] == pwr_mode:
        child.set_active(True)
    if fan_section and label and label[0] == fan_mode:
        child.set_active(True)
updating_menu = False

for child in main_app_menu.get_children():
    label = child.get_label()
    if label:
        regex = re.compile(r"(\d+)")
        m = regex.match(label)
        if m != None:
            no = eval(m.group(1))
            if no == 100:
                no = 0
            else:
                no -= 5
            if no == chg_mode_no:
                child.set_active(True)
                break

running = threading.Event()
running.set()
threading.Thread(target=mode_change_monitor, args=[running]).start()

gtk.main()
