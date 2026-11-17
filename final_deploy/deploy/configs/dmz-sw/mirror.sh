#!/bin/sh
# SPAN (port mirroring) для сенсора IDS.
# Все порты бриджа ДМЗ живут в netns узла dmz-sw, поэтому tc mirred может
# зеркалировать ingress каждого порта на порт сенсора (to-ids).
# Сеть при этом остаётся коммутатором (без режима "хаба").
BR="dmz-br"
IDSPORT="to-ids"

# дождёмся появления бриджа и портов
i=0
while [ ! -d "/sys/class/net/${BR}/brif" ] && [ "$i" -lt 30 ]; do
    sleep 1
    i=$((i + 1))
done

for p in /sys/class/net/${BR}/brif/*; do
    [ -e "$p" ] || continue
    port=$(basename "$p")
    [ "$port" = "$IDSPORT" ] && continue
    tc qdisc add dev "$port" clsact 2>/dev/null || true
    tc filter add dev "$port" ingress matchall \
        action mirred egress mirror dev "$IDSPORT" 2>/dev/null || true
done

echo "[dmz-sw] SPAN: mirroring портов ${BR} -> ${IDSPORT}: $(ls /sys/class/net/${BR}/brif/ 2>/dev/null | tr '\n' ' ')"
