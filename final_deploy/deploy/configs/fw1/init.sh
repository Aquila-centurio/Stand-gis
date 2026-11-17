#!/bin/sh
# fw1 — внешний межсетевой экран (edge).
#   eth1 = внешняя сеть, eth2 = ДМЗ
set -eu

WAN_ADDR="${WAN_ADDR:?WAN_ADDR не задан}"
DMZ_ADDR="${DMZ_ADDR:?DMZ_ADDR не задан}"
LAN_NET="${LAN_NET:?LAN_NET не задан}"
FW2_DMZ="${FW2_DMZ:?FW2_DMZ не задан}"

echo "[fw1] настройка интерфейсов"
ip link set eth1 up
ip link set eth2 up
ip addr add "$WAN_ADDR" dev eth1
ip addr add "$DMZ_ADDR" dev eth2

# Маршрут в приватную сеть — через внутренний МЭ (fw2).
# Без него ответы из ДМЗ во LAN терялись бы в mgmt-маршруте.
ip route add "$LAN_NET" via "$FW2_DMZ"

# Форвардинг (продублировано через sysctls в topology.yml)
sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "[fw1] применение правил nftables"
nft -f /etc/clab/nftables.conf

# DNS узла (mgmt-сети нет)
echo "nameserver 10.10.10.10" > /etc/resolv.conf

# локальное протоколирование событий firewall (nft log group -> ulogd -> файл)
mkdir -p /var/log
setsid ulogd -c /etc/clab/ulogd.conf >/var/log/ulogd.out 2>&1 </dev/null &
sleep 1

echo "[fw1] готово"
ip -br addr
ip route
