#!/bin/bash
# Create the virtual phone on first run, then boot it on the X display.
set -e

AVD_NAME=phone
mkdir -p "${ANDROID_AVD_HOME}"

if [ ! -e /dev/kvm ]; then
    echo "ERROR: /dev/kvm is missing. Enable virtualization (VT-x/AMD-V) in your BIOS"
    echo "       and start the container with --device /dev/kvm (docker compose does this)."
    sleep 30
    exit 1
fi

if [ ! -f "${ANDROID_AVD_HOME}/${AVD_NAME}.ini" ]; then
    echo "Creating virtual phone '${AVD_NAME}' (first run)..."
    echo no | avdmanager create avd --force -n "${AVD_NAME}" -k "${SYSTEM_IMAGE}" -d pixel_6
    cfg="${ANDROID_AVD_HOME}/${AVD_NAME}.avd/config.ini"
    # Drop the Pixel skin so the screen size below is used, then apply our settings.
    sed -i '/^skin\./d;/^hw\.lcd\./d;/^hw\.ramSize/d;/^disk\.dataPartition\.size/d;/^hw\.keyboard/d;/^hw\.mainKeys/d;/^showDeviceFrame/d;/^hw\.gpu\./d;/^hw\.cpu\.ncore/d' "${cfg}"
    cat >> "${cfg}" <<CFG
hw.lcd.width=${PHONE_WIDTH}
hw.lcd.height=${PHONE_HEIGHT}
hw.lcd.density=${PHONE_DENSITY}
hw.ramSize=${PHONE_RAM_MB}
hw.cpu.ncore=${PHONE_CORES}
disk.dataPartition.size=${PHONE_STORAGE}
hw.keyboard=yes
hw.mainKeys=no
hw.gpu.enabled=yes
hw.gpu.mode=${GPU_MODE}
showDeviceFrame=no
CFG
fi

# Leftover lock files from an unclean stop would block the boot.
rm -f "${ANDROID_AVD_HOME}/${AVD_NAME}.avd/"*.lock

until [ -e /tmp/.X11-unix/X0 ]; do sleep 1; done

# Stretch the emulator window to fill the whole virtual display, so the phone
# fills the browser instead of sitting small in a corner.
fit_window() {
    local wid
    wid="$(xdotool search --name "Android Emulator - " 2>/dev/null | head -1)"
    [ -n "${wid}" ] || return 1
    xdotool windowmove "${wid}" 0 0 windowsize "${wid}" "${PHONE_WIDTH}" "${PHONE_HEIGHT}"
}

# Fit the window, then apply speed-ups once Android has booted (runs in the background).
(
    until fit_window; do sleep 1; done
    sleep 3
    fit_window || true
    adb wait-for-device
    until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; done
    adb shell settings put global window_animation_scale 0.5
    adb shell settings put global transition_animation_scale 0.5
    adb shell settings put global animator_duration_scale 0.5
    adb shell settings put system screen_off_timeout 2147483647
    adb shell svc power stayon true
    fit_window || true
    echo "=================================================="
    echo " Phone booted. Open http://localhost:6080 in a browser"
    echo "=================================================="
) &

exec emulator -avd "${AVD_NAME}" \
    -gpu "${GPU_MODE}" \
    -memory "${PHONE_RAM_MB}" \
    -cores "${PHONE_CORES}" \
    -no-audio \
    -no-boot-anim \
    -no-snapshot \
    -netdelay none -netspeed full
