#!/bin/bash
# Обёртка ENTRYPOINT для captive-портала (NAS).
set -uo pipefail

ADDR="${ADDR:?ADDR не задан}"
GW="${GW:?GW не задан}"

echo "[portal] ожидание eth1..."
while ! ip link show eth1 >/dev/null 2>&1; do sleep 1; done
ip link set eth1 up
ip addr add "$ADDR" dev eth1 2>/dev/null || true
ip route del default 2>/dev/null || true
ip route add default via "$GW" 2>/dev/null || true
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
echo "nameserver 10.10.10.10" > /etc/resolv.conf

echo "[portal] ip route:"; ip route

echo "[portal] правила nftables"
nft -f /etc/clab/nftables.conf

echo "[portal] запуск веб-портала на :${PORTAL_PORT:-80}"
exec python3 /etc/clab/portal.py
