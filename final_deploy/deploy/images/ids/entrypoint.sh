#!/bin/bash
# Обёртка ENTRYPOINT для Suricata (IDS).
# containerlab подключает линки после старта, поэтому ждём интерфейс,
# переводим его в promiscuous и запускаем штатный entrypoint образа suricata.
set -uo pipefail

IFACE="${IDS_IFACE:-eth1}"

echo "[ids] ожидание ${IFACE}..."
while [ ! -e "/sys/class/net/${IFACE}" ]; do sleep 1; done
ip link set "$IFACE" up
ip link set "$IFACE" promisc on
mkdir -p /var/log/suricata
echo "nameserver 10.10.10.10" > /etc/resolv.conf

echo "[ids] запуск suricata на ${IFACE} (IDS, правила /etc/clab/local.rules)"
exec /docker-entrypoint.sh -i "$IFACE" \
    -k none \
    -S /etc/clab/local.rules \
    --set vars.address-groups.HOME_NET='[10.10.0.0/16]' \
    --set vars.address-groups.EXTERNAL_NET='[198.51.100.0/24]'
