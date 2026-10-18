#!/bin/sh
# Container entry point: prepares the live camera, then starts all services.
rm -f /tmp/camera-ready

# The PC loads the CloudPhoneCam virtual webcam driver into the (shared) kernel.
# Find it by name and create the phone's /dev/video0 for it here, inside the
# container, so it works no matter how the PC's /dev is shared with Docker
# (WSL, Docker Desktop, ...). Other video devices are hidden from the phone so
# that ours is always its "webcam0".
rm -f /dev/video*
for d in /sys/class/video4linux/video*; do
    [ "$(cat "$d/name" 2>/dev/null)" = CloudPhoneCam ] || continue
    dev="$(cat "$d/dev")"
    if mknod -m 666 /dev/video0 c "${dev%%:*}" "${dev##*:}"; then
        echo "Live camera device found ($(basename "$d"), $dev)."
    fi
    break
done
[ -e /dev/video0 ] || echo "No live camera device (load it on the PC with ./phone.sh start)."

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
