#!/bin/sh
# Общий init для хостовых узлов (attacker, web, db, ext-web).
# Адрес и шлюз задаются через env узла в topology.clab.yml.
set -eu

ADDR="${ADDR:?ADDR не задан}"
GW="${GW:-}"
HOSTNAME="$(hostname)"

echo "[$HOSTNAME] настройка интерфейса eth1: $ADDR"
ip link set eth1 up
ip addr add "$ADDR" dev eth1

if [ -n "$GW" ]; then
    ip route replace default via "$GW"
    echo "[$HOSTNAME] шлюз по умолчанию: $GW"
fi

# Необязательный маршрут во внутреннюю сеть (для узлов ДМЗ, к которым
# обращаются из приватной сети — иначе ответы уйдут в fw1 и потеряются).
if [ -n "${INTERNAL_NET:-}" ] && [ -n "${INTERNAL_GW:-}" ]; then
    ip route add "$INTERNAL_NET" via "$INTERNAL_GW"
    echo "[$HOSTNAME] маршрут $INTERNAL_NET via $INTERNAL_GW"
fi

# DNS задаём явно (mgmt-сети у узла нет)
echo "nameserver ${DNS_SERVER:-127.0.0.1}" > /etc/resolv.conf

echo "[$HOSTNAME] готово"
ip -br addr
ip route
