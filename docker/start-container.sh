#!/bin/sh
# Container entry point: prepares the live camera, then starts all services.
rm -f /tmp/camera-ready

# The PC loads a v4l2loopback virtual webcam (CloudPhoneCam) into the (shared) kernel.
# Find it by name and create the phone's /dev/video0 for it here, inside the
# container, so it works no matter how the PC's /dev is shared with Docker
# (WSL, Docker Desktop, ...). Other video devices are hidden from the phone so
# that ours is always its "webcam0".
rm -f /dev/video*
cam=""
for d in /sys/class/video4linux/video*; do
    name="$(cat "$d/name" 2>/dev/null)"
    if [ "$name" = CloudPhoneCam ]; then cam="$d"; break; fi
    # Any other v4l2loopback virtual camera (e.g. one the system created itself).
    if [ -z "$cam" ] && { [ -e "$d/max_openers" ] || [ "${name#Dummy video device}" != "$name" ]; }; then
        cam="$d"
    fi
done
for d in $cam; do
    dev="$(cat "$d/dev")"
    if mknod -m 666 /dev/video0 c "${dev%%:*}" "${dev##*:}"; then
        echo "Live camera device found ($(basename "$d"): $(cat "$d/name" 2>/dev/null), $dev)."
    fi
done
[ -e /dev/video0 ] || echo "No live camera device (load it on the PC with ./phone.sh start)."

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
