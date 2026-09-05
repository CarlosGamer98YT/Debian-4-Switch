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
     echo "$2" > /var/lib/nvpmodel/custom_fan_mode 2>/dev/null || true
     chmod 666 /var/lib/nvpmodel/custom_fan_mode 2>/dev/null || true

     MODE="$2"
     TARGET_PWM=128
     PROFILE_NAME="Console"

     if [ "$MODE" -eq 1 ]; then
         # Handheld mode: quiet / lower RPM (~30% / 3200 RPM)
         TARGET_PWM=77
         PROFILE_NAME="Handheld"
     elif [ "$MODE" -eq 2 ]; then
         # Cool mode: high airflow cooling (~75% / 7800 RPM)
         TARGET_PWM=192
         PROFILE_NAME="Cool"
     elif [ "$MODE" -eq 3 ]; then
         # Full 100% mode: maximum speed (100% / 10000 RPM)
         TARGET_PWM=255
         PROFILE_NAME="Cool"
     else
         # Console mode (0): balanced docked speed (~50% / 5200 RPM)
         TARGET_PWM=128
         PROFILE_NAME="Console"
     fi

     # Apply immediately to pwm-fan
     for p in /sys/devices/platform/pwm-fan /sys/bus/platform/devices/pwm-fan /sys/devices/pwm-fan; do
         if [ -d "$p" ]; then
             # 1. Set fan profile first (because profile change can reset driver caps)
             [ -w "$p/fan_profile" ] && echo "$PROFILE_NAME" > "$p/fan_profile" 2>/dev/null || true
             # 2. Unlock caps so TARGET_PWM is never clamped by kernel driver
             [ -w "$p/state_cap" ] && echo 9 > "$p/state_cap" 2>/dev/null || true
             [ -w "$p/pwm_cap" ] && echo 255 > "$p/pwm_cap" 2>/dev/null || true
             # 3. Fast ramp speed
             [ -w "$p/step_time" ] && echo 20 > "$p/step_time" 2>/dev/null || true
             # 4. Disable continuous thermal governor so manual PWM persists
             [ -w "$p/temp_control" ] && echo 0 > "$p/temp_control" 2>/dev/null || true
             # 5. Ensure tachometer is enabled
             if [ -w "$p/tach_enable" ]; then
                 [ "$(cat "$p/tach_enable" 2>/dev/null)" != "1" ] && echo 1 > "$p/tach_enable" 2>/dev/null || true
             fi
             # 6. Set desired PWM duty
             [ -w "$p/target_pwm" ] && echo "$TARGET_PWM" > "$p/target_pwm" 2>/dev/null || true
             # 7. Grant full read/write permissions for sysfs nodes
             chmod 666 "$p"/* 2>/dev/null || true
         fi
     done

     # Apply to thermal-fan-est
     for est in /sys/devices/platform/thermal-fan-est /sys/bus/platform/devices/thermal-fan-est /sys/devices/thermal-fan-est; do
         if [ -d "$est" ]; then
             [ -w "$est/fan_profile" ] && echo "$PROFILE_NAME" > "$est/fan_profile" 2>/dev/null || true
             chmod 666 "$est"/* 2>/dev/null || true
         fi
     done

     # Update status file for nvpmodel compatibility
     if [ -f /var/lib/nvpmodel/status ]; then
         sed -i "s/fmode:[^ ]*/fmode:${PROFILE_NAME}/g" /var/lib/nvpmodel/status 2>/dev/null || true
     else
         echo "pmode:0000 fmode:${PROFILE_NAME}" > /var/lib/nvpmodel/status 2>/dev/null || true
     fi
     exit 0
elif [ "$1" -eq 11 ]; then # Get custom fan mode.
     if [ -f "/var/lib/nvpmodel/custom_fan_mode" ]; then
         exit $(cat /var/lib/nvpmodel/custom_fan_mode 2>/dev/null || echo 0)
     fi
     exit 0
fi
