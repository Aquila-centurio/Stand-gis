#!/bin/sh
# dns — резолвер ДМЗ (unbound). Единая точка резолвинга для стенда.
#   * зона otlichnik.lab форвардится на FreeIPA (внутренняя сеть)
#   * остальные имена — на внешний DNS (ext-dns) ЧЕРЕЗ fw1
set -eu

ADDR="${ADDR:?ADDR не задан}"
INTERNAL_NET="${INTERNAL_NET:?INTERNAL_NET не задан}"
INTERNAL_GW="${INTERNAL_GW:?INTERNAL_GW не задан}"
DMZ_GW="${DMZ_GW:?DMZ_GW не задан}"

echo "[dns] настройка интерфейса eth1: $ADDR"
ip link set eth1 up
ip addr add "$ADDR" dev eth1

# Внутренняя сеть — через fw2 (шлюз ДМЗ->LAN)
ip route add "$INTERNAL_NET" via "$INTERNAL_GW"

# Дефолт — через fw1 во внешний сегмент (замкнутый контур).
ip route replace default via "$DMZ_GW"

# dns резолвит себя сам
echo "nameserver 127.0.0.1" > /etc/resolv.conf

echo "[dns] запуск unbound"
unbound -c /etc/clab/unbound.conf &

sleep 1
echo "[dns] готово"
ip -br addr
ip route
