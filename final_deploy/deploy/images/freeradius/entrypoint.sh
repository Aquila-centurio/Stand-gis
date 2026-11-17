#!/bin/bash
# Обёртка ENTRYPOINT для FreeRADIUS.
# Ждёт data-интерфейс (containerlab подключает линки после старта), настраивает
# IP, раскладывает конфиги (clients, ldap, default) и запускает radiusd.
set -uo pipefail

ADDR="${ADDR:?ADDR не задан}"
GW="${GW:?GW не задан}"

if command -v ip >/dev/null 2>&1; then
    IPCMD=(ip)
else
    IPCMD=(/usr/local/bin/busybox ip)
fi

echo "[radius] ожидание eth1..."
while ! "${IPCMD[@]}" link show eth1 >/dev/null 2>&1; do sleep 1; done
"${IPCMD[@]}" link set eth1 up
"${IPCMD[@]}" addr add "$ADDR" dev eth1 2>/dev/null || true
"${IPCMD[@]}" route del default 2>/dev/null || true
"${IPCMD[@]}" route add default via "$GW" 2>/dev/null || true

# Внутренняя сеть — через fw2 (напрямую в ДМЗ), а не через fw1.
if [ -n "${INTERNAL_NET:-}" ] && [ -n "${INTERNAL_GW:-}" ]; then
    "${IPCMD[@]}" route add "$INTERNAL_NET" via "$INTERNAL_GW" 2>/dev/null || true
fi

echo "nameserver 10.10.10.10" > /etc/resolv.conf

echo "[radius] ip route:"; "${IPCMD[@]}" route 2>/dev/null || true

# Ждём, пока интерфейс поднимется и станет доступен LDAP (IPA).
LDAP_HOST="${LDAP_HOST:-}"
LDAP_PORT="${LDAP_PORT:-389}"
if [ -n "$LDAP_HOST" ]; then
    echo "[radius] ожидание LDAP ${LDAP_HOST}:${LDAP_PORT} ..."
    i=0
    while ! timeout 2 bash -c "exec 3<>/dev/tcp/${LDAP_HOST}/${LDAP_PORT}" 2>/dev/null; do
        sleep 2
        i=$((i + 1))
        if [ $((i % 10)) -eq 0 ]; then
            echo "[radius] LDAP недоступен (${i}) — проверь маршрут и правило DMZ->IPA:389 на fw2"
        fi
    done
    echo "[radius] LDAP доступен"
    echo "[radius] ожидание сервисного аккаунта ${LDAP_BIND_DN} ..."
    while ! ldapwhoami -x -H "ldap://${LDAP_HOST}" -D "${LDAP_BIND_DN}" -w "${LDAP_PASSWORD}" >/dev/null 2>&1; do
        sleep 2
    done
    echo "[radius] сервисный аккаунт доступен"
fi

RADDB=/etc/raddb
[ -d "$RADDB" ] || RADDB=/etc/freeradius/3.0
echo "[radius] каталог конфигов: $RADDB"

# clients.conf
cp -f /etc/clab/clients.conf "$RADDB/clients.conf"

# модуль ldap (подстановка параметров)
sed -e "s|@@LDAP_SERVER@@|${LDAP_SERVER}|g" \
    -e "s|@@LDAP_BIND_DN@@|${LDAP_BIND_DN}|g" \
    -e "s|@@LDAP_PASSWORD@@|${LDAP_PASSWORD}|g" \
    -e "s|@@LDAP_BASE_DN@@|${LDAP_BASE_DN}|g" \
    /etc/clab/ldap.template > "$RADDB/mods-available/ldap"
ln -sf ../mods-available/ldap "$RADDB/mods-enabled/ldap"

# site default
cp -f /etc/clab/site-default.conf "$RADDB/sites-available/default"
ln -sf ../sites-available/default "$RADDB/sites-enabled/default"
[ -e "$RADDB/sites-enabled/inner-tunnel" ] || ln -sf ../sites-available/inner-tunnel "$RADDB/sites-enabled/inner-tunnel" 2>/dev/null || true

# права (radiusd работает под непривилегированным пользователем)
for u in freerad radiusd radius; do
    if id "$u" >/dev/null 2>&1; then
        chown "$u" "$RADDB/clients.conf" "$RADDB/mods-available/ldap" "$RADDB/sites-available/default" 2>/dev/null || true
        break
    fi
done

echo "[radius] запуск radiusd"

find_radiusd() {
    for c in radiusd freeradius; do
        p="$(command -v "$c" 2>/dev/null || true)"
        [ -n "$p" ] && { printf '%s' "$p"; return 0; }
    done
    for p in /usr/sbin/radiusd /usr/local/sbin/radiusd /usr/local/bin/radiusd \
             /opt/freeradius/sbin/radiusd /usr/sbin/freeradius /usr/local/sbin/freeradius; do
        [ -x "$p" ] && { printf '%s' "$p"; return 0; }
    done
    find / -maxdepth 6 -type f \( -name radiusd -o -name freeradius \) 2>/dev/null | head -n1
}

RADIUSD="$(find_radiusd)"
if [ -z "$RADIUSD" ]; then
    echo "[radius] radiusd НЕ найден. PATH=$PATH"
    echo "[radius] содержимое /usr/sbin:"; ls -la /usr/sbin 2>/dev/null | grep -iE 'radius|freerad' || true
    echo "[radius] содержимое /usr/local/sbin:"; ls -la /usr/local/sbin 2>/dev/null | grep -iE 'radius|freerad' || true
    echo "[radius] контейнер остаётся для отладки (sleep infinity)"
    exec sleep infinity
fi

echo "[radius] radiusd: $RADIUSD, конфиг: $RADDB"
exec "$RADIUSD" -d "$RADDB" -f -l stdout

