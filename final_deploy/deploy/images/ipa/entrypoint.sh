#!/bin/bash
# Обёртка ENTRYPOINT для FreeIPA.
#
# ВАЖНО: containerlab подключает линки ПОСЛЕ старта контейнера, поэтому на
# старте data-интерфейса eth1 ещё нет. Ждём его появления, затем настраиваем
# IP/маршрут и только после этого запускаем штатный init (systemd), который
# выполняет ipa-server-install.
set -uo pipefail

ADDR="${ADDR:?ADDR не задан}"
GW="${GW:?GW не задан}"
FQDN="${IPA_FQDN:-ipa.otlichnik.lab}"

# Используем штатный `ip`, если он есть, иначе busybox.
if command -v ip >/dev/null 2>&1; then
    IPCMD=(ip)
else
    IPCMD=(/usr/local/bin/busybox ip)
fi

echo "[ipa] ожидание data-интерфейса eth1..."
t=0
while ! "${IPCMD[@]}" link show eth1 >/dev/null 2>&1; do
    sleep 1
    t=$((t + 1))
    if [ $((t % 10)) -eq 0 ]; then
        echo "[ipa] eth1 пока не появился (${t}s)"
    fi
done
echo "[ipa] eth1 появился"

"${IPCMD[@]}" link set eth1 up
"${IPCMD[@]}" addr add "$ADDR" dev eth1 2>/dev/null || true

# Дефолт заменяем (Docker уже поставил маршрут через mgmt).
"${IPCMD[@]}" route del default 2>/dev/null || true
"${IPCMD[@]}" route add default via "$GW"

SELF_IP="${ADDR%%/*}"
SHORT="${FQDN%%.*}"

# containerlab/Docker кладут в /etc/hosts запись "<mgmt-ip> <short-name>", из-за
# чего ipa-server-install ругается на несовпадение канонического имени.
# Убираем такие записи и прописываем корректное соответствие.
if [ -w /etc/hosts ]; then
    grep -vE "(^|[[:space:]])${SHORT}([[:space:]]|$)" /etc/hosts > /tmp/hosts.new 2>/dev/null \
        && cat /tmp/hosts.new > /etc/hosts || true
fi
if ! grep -qE "[[:space:]]${FQDN}([[:space:]]|$)" /etc/hosts; then
    echo "${SELF_IP} ${FQDN} ${SHORT}" >> /etc/hosts
fi

echo "[ipa] настройка завершена, запуск штатного init (systemd)"
echo "nameserver 127.0.0.1" > /etc/resolv.conf
exec /usr/local/sbin/init "$@"
