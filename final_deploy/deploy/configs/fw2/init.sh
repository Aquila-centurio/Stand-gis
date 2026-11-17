#!/bin/sh
# fw2 — внутренний межсетевой экран.
#   eth1 = ДМЗ, eth2 = приватная сеть
set -eu

DMZ_ADDR="${DMZ_ADDR:?DMZ_ADDR не задан}"
LAN_ADDR="${LAN_ADDR:?LAN_ADDR не задан}"
DMZ_GW="${DMZ_GW:?DMZ_GW не задан}"

echo "[fw2] настройка интерфейсов"
ip link set eth1 up
ip link set eth2 up
ip addr add "$DMZ_ADDR" dev eth1
ip addr add "$LAN_ADDR" dev eth2

# Аплинк fw2 — во внешний МЭ (fw1) через ДМЗ.
# replace, а не add: Docker уже создал дефолт через mgmt-шлюз.
ip route replace default via "$DMZ_GW"

sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "[fw2] применение правил nftables"
nft -f /etc/clab/nftables.conf

# DNS узла (mgmt-сети нет)
echo "nameserver 10.10.10.10" > /etc/resolv.conf

# локальное протоколирование событий firewall (nft log group -> ulogd -> файл)
mkdir -p /var/log
setsid ulogd -c /etc/clab/ulogd.conf >/var/log/ulogd.out 2>&1 </dev/null &
sleep 1

echo "[fw2] готово"
ip -br addr
ip route
