#!/bin/bash
# Control the cloud phone.
set -e
cd "$(dirname "$0")"

[ -f .env ] || cp .env.example .env
set -a; . ./.env; set +a
PORT="${WEB_PORT:-6080}"

CAM_OPTS=(devices=1 video_nr=42 card_label=CloudPhoneCam exclusive_caps=1)
# Camera drivers for WSL: ready-made ones shipped in this repo for known WSL
# kernels, or ones built on this PC by setup-camera.sh.
CAM_PREBUILT="camera-drivers/$(uname -r)"
CAM_BUILT="${HOME}/.local/share/cloudphone/$(uname -r)"

adb_in() { docker exec cloudphone adb "$@"; }

# Include the camera device in the container only when it exists.
compose() {
    if [ -e /dev/video42 ]; then
        docker compose -f docker-compose.yml -f docker-compose.camera.yml "$@"
    else
        docker compose -f docker-compose.yml "$@"
    fi
}

is_wsl() { grep -qi microsoft /proc/version; }

cam_driver_dir() {
    local d
    for d in "${CAM_PREBUILT}" "${CAM_BUILT}"; do
        [ -f "${d}/v4l2loopback.ko" ] && { echo "${d}"; return 0; }
    done
    return 1
}

camera_driver_installed() {
    if is_wsl; then cam_driver_dir > /dev/null; else modinfo v4l2loopback > /dev/null 2>&1; fi
}

module_loaded() { grep -q "^$1 " /proc/modules 2> /dev/null; }

camera_on() {
    [ -e /dev/video42 ] && return 0
    if is_wsl; then
        local d
        d="$(cam_driver_dir)" || { echo "No camera driver for kernel $(uname -r) yet - run ./setup-camera.sh"; return 1; }
        echo "Loading camera driver (may ask for your Ubuntu password)..."
        if ! module_loaded videodev && ! sudo modprobe videodev 2> /dev/null; then
            module_loaded led_class || sudo insmod "${d}/led-class.ko" 2> /dev/null || true
            module_loaded mc || sudo insmod "${d}/mc.ko" 2> /dev/null || true
            sudo insmod "${d}/videodev.ko" || { sudo dmesg | tail -n 5; return 1; }
        fi
        if ! module_loaded v4l2loopback; then
            sudo insmod "${d}/v4l2loopback.ko" "${CAM_OPTS[@]}" || { sudo dmesg | tail -n 5; return 1; }
        fi
    else
        sudo modprobe v4l2loopback "${CAM_OPTS[@]}"
    fi
    for _ in 1 2 3 4 5; do [ -e /dev/video42 ] && break; sleep 1; done
    [ -e /dev/video42 ] || { echo "Driver loaded but /dev/video42 did not appear."; return 1; }
    echo "Camera device ready (/dev/video42)."
}

case "$1" in
    start)
        if [ "${LISTEN_ADDR:-127.0.0.1}" != "127.0.0.1" ] && [ -z "${VNC_PASSWORD}" ]; then
            echo "LISTEN_ADDR=${LISTEN_ADDR} exposes the phone to your network."
            echo "Set VNC_PASSWORD in .env first."
            exit 1
        fi
        [ -e /dev/kvm ] || { echo "/dev/kvm missing - run ./setup.sh first."; exit 1; }
        echo "== Live camera"
        cam_msg=""
        if ! camera_driver_installed; then
            cam_msg="no camera driver for kernel $(uname -r) - run ./setup-camera.sh"
        elif ! camera_on; then
            cam_msg="the camera driver failed to load (error above)"
        fi
        echo "== Phone"
        echo "Building and starting (first build downloads ~2 GB, be patient)..."
        compose up -d --build
        if [ -z "${cam_msg}" ] && ! docker exec cloudphone test -e /dev/video0; then
            cam_msg="the phone container did not get the camera device"
        fi
        echo
        echo "=================================================================="
        if [ -z "${cam_msg}" ]; then
            echo " LIVE CAMERA: ON  (click 'Camera: off' on the page to send your webcam)"
        else
            echo " LIVE CAMERA: OFF - ${cam_msg}"
            echo " Send this whole output (and ./phone.sh doctor) to get it fixed."
        fi
        echo " Booting Android (1-3 minutes). Open: http://localhost:${PORT}"
        echo "=================================================================="
        ;;
    camera-on)
        camera_on
        echo "Now run: ./phone.sh start"
        ;;
    stop)
        compose stop
        ;;
    restart)
        compose restart
        ;;
    logs)
        compose logs -f --tail=100
        ;;
    status)
        compose ps
        if [ "$(adb_in shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
            echo "Android: booted - http://localhost:${PORT}"
        else
            echo "Android: still booting (or stopped)"
        fi
        ;;
    install)
        [ -f "$2" ] || { echo "Usage: ./phone.sh install app.apk"; exit 1; }
        docker cp "$2" cloudphone:/tmp/app.apk
        adb_in install -r /tmp/app.apk
        docker exec cloudphone rm -f /tmp/app.apk
        ;;
    upload)
        [ -f "$2" ] || { echo "Usage: ./phone.sh upload photo.jpg"; exit 1; }
        curl -fsS ${VNC_PASSWORD:+-u "phone:${VNC_PASSWORD}"} -F "file=@$2" "http://localhost:${PORT}/upload"
        echo
        ;;
    doctor)
        # Check every step the live camera needs, and say how to fix the first failure.
        ok()   { echo "  [OK]   $1"; }
        bad()  { echo "  [FAIL] $1"; echo "         Fix: $2"; exit 1; }
        echo "Camera check:"
        if grep -qi microsoft /proc/version; then ok "Ubuntu on WSL, kernel $(uname -r)"; else ok "Ubuntu, kernel $(uname -r)"; fi
        if is_wsl; then
            cam_driver_dir > /dev/null && ok "camera driver for this kernel: $(cam_driver_dir)" \
                || bad "no camera driver for kernel $(uname -r)" "git pull, or ./setup-camera.sh  (if it already ran, send its output)"
        else
            modinfo v4l2loopback > /dev/null 2>&1 && ok "camera driver installed" \
                || bad "camera driver not installed" "./setup-camera.sh"
        fi
        if [ ! -e /dev/video42 ]; then
            echo "  ...    loading the camera driver:"
            camera_on 2>&1 | sed 's/^/         /' || true
        fi
        [ -e /dev/video42 ] && ok "camera device /dev/video42 exists" \
            || bad "camera device /dev/video42 missing (driver failed to load, see the error above)" \
                   "send this output to get it fixed"
        docker ps --format '{{.Names}}' | grep -qx cloudphone && ok "phone container is running" \
            || bad "phone container not running" "./phone.sh start"
        docker exec cloudphone test -e /dev/video0 && ok "phone container has the camera" \
            || bad "phone container was started without the camera" "./phone.sh start  (recreates it with the camera)"
        docker exec cloudphone test -e /tmp/camera-ready && ok "camera feed is running" \
            || bad "camera feed not running: $(compose logs --tail=300 2>/dev/null | grep 'camera feed stopped' | tail -1)" \
                   "send this output to get it fixed"
        if compose logs --tail=2000 2>/dev/null | grep -q "Live camera enabled"; then
            ok "phone started with the live camera"
        else
            bad "the phone was started before the camera was ready" "./phone.sh restart"
        fi
        echo "All good: open the page, click 'Camera: off' so it turns red, and allow the webcam."
        ;;
    crashlog)
        # Recent app crashes (Java and native), newest last.
        adb_in logcat -d -b crash -v time | tail -n "${2:-80}"
        ;;
    home)  adb_in shell input keyevent KEYCODE_HOME ;;
    back)  adb_in shell input keyevent KEYCODE_BACK ;;
    rotate)
        cur="$(adb_in shell settings get system user_rotation | tr -d '\r')"
        adb_in shell settings put system accelerometer_rotation 0
        adb_in shell settings put system user_rotation $(( (cur + 1) % 2 ))
        ;;
    shell)
        docker exec -it cloudphone adb shell
        ;;
    reset)
        read -r -p "This ERASES the phone (apps, Google account, files). Type 'yes': " ok
        [ "$ok" = "yes" ] || exit 1
        compose down -v
        echo "Phone erased. Run ./phone.sh start to create a fresh one."
        ;;
    *)
        echo "Usage: ./phone.sh {start|stop|restart|status|logs|install <apk>|upload <file>|crashlog|doctor|home|back|rotate|shell|reset}"
        exit 1
        ;;
esac
