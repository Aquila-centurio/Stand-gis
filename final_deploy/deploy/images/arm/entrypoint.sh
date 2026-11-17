#!/bin/bash
# Обёртка ENTRYPOINT для АРМ с графикой (Xvfb + openbox + x11vnc + noVNC + Firefox).
set -uo pipefail

ADDR="${ADDR:?ADDR не задан}"
GW="${GW:?GW не задан}"
GEO="${GEO:-1280x800x24}"

echo "[arm] ожидание eth1..."
while ! ip link show eth1 >/dev/null 2>&1; do sleep 1; done
ip link set eth1 up
ip addr add "$ADDR" dev eth1 2>/dev/null || true
ip route del default 2>/dev/null || true
ip route add default via "$GW" 2>/dev/null || true
echo "[arm] ip route:"; ip route

export DISPLAY=:0
export HOME=/root

echo "[arm] Xvfb ${GEO}"
Xvfb :0 -screen 0 "$GEO" -nolisten tcp >/tmp/xvfb.log 2>&1 &
sleep 1

echo "[arm] openbox"
openbox >/tmp/openbox.log 2>&1 &

echo "[arm] x11vnc :5900 + noVNC :6080"
x11vnc -display :0 -forever -shared -nopw -rfbport 5900 -quiet >/tmp/x11vnc.log 2>&1 &
websockify --web /usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &

echo "[arm] xterm + firefox"
xterm -fa Monospace -fs 12 >/tmp/xterm.log 2>&1 &
# Сразу открываем внешний сайт: пока АРМ не авторизован, nftables на портале
# перехватит запрос и покажет страницу входа. После входа браузер вернётся
# на этот же URL (см. configs/portal/portal.py).
firefox-esr --no-remote "${HOME_URL:-http://example.com/}" >/tmp/firefox.log 2>&1 &

echo "[arm] графический АРМ запущен (noVNC на :6080)"
wait
