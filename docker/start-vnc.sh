#!/bin/bash
# Share the virtual X display over VNC (noVNC connects to this on localhost:5900).
set -e

until [ -e /tmp/.X11-unix/X0 ]; do sleep 1; done

args=(-display :0 -forever -shared -rfbport 5900 -localhost -xkb -noxrecord -noxfixes -noxdamage -defer 10 -wait 10 -quiet)
if [ -n "${VNC_PASSWORD}" ]; then
    mkdir -p /root/.vnc
    x11vnc -storepasswd "${VNC_PASSWORD}" /root/.vnc/passwd > /dev/null
    args+=(-rfbauth /root/.vnc/passwd)
else
    args+=(-nopw)
fi

exec x11vnc "${args[@]}"
