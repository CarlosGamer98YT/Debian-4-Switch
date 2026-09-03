#!/bin/bash
# nvpmodel_helper.sh: Helper for panel modes, charging limits, and fan control

if   [ "$1" -eq 1 ]; then # Get panel color mode.
     exit $(cat /sys/devices/50000000.host1x/tegradc.0/panel_color_mode 2>/dev/null || echo 0)
elif [ "$1" -eq 2 ]; then # Set panel color mode.
     if [ ! -e "/sys/devices/50000000.host1x/tegradc.0/panel_color_mode" ]; then exit 1; fi
     echo "$2" > /sys/devices/50000000.host1x/tegradc.0/panel_color_mode
     echo "$2" > /var/lib/nvpmodel/color_mode
elif [ "$1" -eq 3 ]; then # Get panel color mode supported.
     if [ -e "/sys/devices/50000000.host1x/tegradc.0/panel_color_mode" ]; then exit 1; else exit 0; fi
elif [ "$1" -eq 4 ]; then # Get auto profile.
     if [ ! -e "/var/lib/nvpmodel/auto_profiles" ]; then exit 0; fi
     if grep -q 0 "/var/lib/nvpmodel/auto_profiles" 2>/dev/null; then exit 0; else exit 1; fi
elif [ "$1" -eq 5 ]; then # Set auto profile.
     echo "$2" > /var/lib/nvpmodel/auto_profiles
elif [ "$1" -eq 6 ]; then # Get current charging limit.
     exit $(cat /sys/class/power_supply/usb/charge_control_limit 2>/dev/null || echo 0)
elif [ "$1" -eq 7 ]; then # Set charging limit.
     echo "$2" > /sys/class/power_supply/usb/charge_control_limit 2>/dev/null || true
     echo "$2" > /var/lib/nvpmodel/charging_status 2>/dev/null || true
elif [ "$1" -eq 8 ]; then # Get charging limit supported.
     if [ -e "/sys/class/power_supply/usb/charge_control_limit" ]; then exit 1; else exit 0; fi
elif [ "$1" -eq 9 ]; then # Get saved charging limit.
     if [ ! -e "/var/lib/nvpmodel/charging_status" ]; then exit 0; fi
     exit $(cat /var/lib/nvpmodel/charging_status 2>/dev/null || echo 0)
elif [ "$1" -eq 10 ]; then # Set fan mode (0: Console, 1: Handheld, 2: Cool, 3: Full 100%)
     mkdir -p /var/lib/nvpmodel 2>/dev/null || true
     if [ "$2" -eq 3 ]; then
         echo 3 > /var/lib/nvpmodel/custom_fan_mode 2>/dev/null || true
         for p in /sys/devices/platform/pwm-fan /sys/bus/platform/devices/pwm-fan /sys/devices/pwm-fan; do
             if [ -d "$p" ]; then
                 echo 255 > "$p/target_pwm" 2>/dev/null || true
             fi
         done
         for cd in /sys/class/thermal/cooling_device*; do
             if [ -f "$cd/type" ] && grep -qi "pwm-fan" "$cd/type" 2>/dev/null; then
                 cat "$cd/max_state" > "$cd/cur_state" 2>/dev/null || true
             fi
         done
     else
         echo "$2" > /var/lib/nvpmodel/custom_fan_mode 2>/dev/null || true
         if [ "$2" -eq 0 ]; then
             nvpmodel -d Console 2>/dev/null || true
         elif [ "$2" -eq 1 ]; then
             nvpmodel -d Handheld 2>/dev/null || true
         elif [ "$2" -eq 2 ]; then
             nvpmodel -d Cool 2>/dev/null || true
         fi
     fi
elif [ "$1" -eq 11 ]; then # Get custom fan mode.
     if [ -f "/var/lib/nvpmodel/custom_fan_mode" ]; then
         exit $(cat /var/lib/nvpmodel/custom_fan_mode 2>/dev/null || echo 0)
     fi
     exit 0
fi
