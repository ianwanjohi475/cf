#!/bin/bash
# Control the cloud phone.
set -e
cd "$(dirname "$0")"

[ -f .env ] || cp .env.example .env
set -a; . ./.env; set +a
PORT="${WEB_PORT:-6080}"

CAM_OPTS=(devices=1 video_nr=42 card_label=CloudPhoneCam exclusive_caps=1)
CAM_DIR="${HOME}/.local/share/cloudphone"
CAM_KO="${CAM_DIR}/v4l2loopback-$(uname -r).ko"

adb_in() { docker exec cloudphone adb "$@"; }

# Include the camera device in the container only when it exists.
compose() {
    if [ -e /dev/video42 ]; then
        docker compose -f docker-compose.yml -f docker-compose.camera.yml "$@"
    else
        docker compose -f docker-compose.yml "$@"
    fi
}

camera_driver_installed() {
    [ -f "${CAM_KO}" ] || { ! grep -qi microsoft /proc/version && modinfo v4l2loopback > /dev/null 2>&1; }
}

camera_on() {
    [ -e /dev/video42 ] && return 0
    if grep -qi microsoft /proc/version; then
        [ -f "${CAM_KO}" ] || { echo "No camera driver yet - run ./setup-camera.sh"; return 1; }
        if ! sudo modprobe videodev 2> /dev/null; then
            sudo insmod "${CAM_DIR}/led-class-$(uname -r).ko" 2> /dev/null || true
            sudo insmod "${CAM_DIR}/mc-$(uname -r).ko" 2> /dev/null || true
            sudo insmod "${CAM_DIR}/videodev-$(uname -r).ko"
        fi
        sudo insmod "${CAM_KO}" "${CAM_OPTS[@]}"
    else
        sudo modprobe v4l2loopback "${CAM_OPTS[@]}"
    fi
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
        if camera_driver_installed; then
            camera_on || echo "Camera could not be enabled; starting without a live camera."
        fi
        echo "Building and starting (first build downloads ~2 GB, be patient)..."
        compose up -d --build
        echo
        echo "Booting Android (1-3 minutes). Open: http://localhost:${PORT}"
        echo "Watch progress with: ./phone.sh logs"
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
        echo "Usage: ./phone.sh {start|stop|restart|status|logs|install <apk>|upload <file>|crashlog|home|back|rotate|shell|reset}"
        exit 1
        ;;
esac
