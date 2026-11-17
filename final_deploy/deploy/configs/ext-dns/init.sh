#!/bin/sh
# ext-dns — имитация DNS-сервера интернета (аналог «GOOGLE DNS» на схеме).
# Отвечает на любые внешние имена фиксированным адресом (catch-all).
set -eu

ADDR="${ADDR:?ADDR не задан}"
GW="${GW:?GW не задан}"
UPSTREAM_IP="${UPSTREAM_IP:-198.51.100.10}"

echo "[ext-dns] настройка интерфейса eth1: $ADDR"
ip link set eth1 up
ip addr add "$ADDR" dev eth1
ip route replace default via "$GW"

echo "nameserver 127.0.0.1" > /etc/resolv.conf

echo "[ext-dns] запуск dnsmasq (catch-all -> $UPSTREAM_IP)"
dnsmasq --keep-in-foreground --no-hosts --no-resolv \
        --address=/#/"$UPSTREAM_IP" &

sleep 1
echo "[ext-dns] готово"
ip -br addr
