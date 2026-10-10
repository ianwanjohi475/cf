#!/bin/bash
# Control the cloud phone.
set -e
cd "$(dirname "$0")"

[ -f .env ] || cp .env.example .env
set -a; . ./.env; set +a
PORT="${WEB_PORT:-6080}"

adb_in() { docker exec cloudphone adb "$@"; }

case "$1" in
    start)
        if [ "${LISTEN_ADDR:-127.0.0.1}" != "127.0.0.1" ] && [ -z "${VNC_PASSWORD}" ]; then
            echo "LISTEN_ADDR=${LISTEN_ADDR} exposes the phone to your network."
            echo "Set VNC_PASSWORD in .env first."
            exit 1
        fi
        [ -e /dev/kvm ] || { echo "/dev/kvm missing - run ./setup.sh first."; exit 1; }
        echo "Building and starting (first build downloads ~2 GB, be patient)..."
        docker compose up -d --build
        echo
        echo "Booting Android (1-3 minutes). Open: http://localhost:${PORT}"
        echo "Watch progress with: ./phone.sh logs"
        ;;
    stop)
        docker compose stop
        ;;
    restart)
        docker compose restart
        ;;
    logs)
        docker compose logs -f --tail=100
        ;;
    status)
        docker compose ps
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
        docker compose down -v
        echo "Phone erased. Run ./phone.sh start to create a fresh one."
        ;;
    *)
        echo "Usage: ./phone.sh {start|stop|restart|status|logs|install <apk>|upload <file>|crashlog|home|back|rotate|shell|reset}"
        exit 1
        ;;
esac
