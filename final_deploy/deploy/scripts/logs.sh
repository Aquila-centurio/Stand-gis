#!/bin/sh
# Показать локальные логи узла стенда.
#
#   sh scripts/logs.sh <узел> [строк]
#   например: sh scripts/logs.sh fw1
#             sh scripts/logs.sh ids 50
#
# Для большинства узлов логи идут в stdout (docker logs). Для отдельных
# узлов источник свой (firewall/IDS/VPN/journal IPA).
set -eu
cd "$(dirname "$0")/.."

NODE="${1:?укажи узел: fw1, fw2, web, ftp, eml, vpn, radius, portal, db, ids, ipa, arm, dns}"
LINES="${2:-40}"
C="clab-gis-${NODE}"

case "$NODE" in
    fw1|fw2)
        echo "== $NODE: /var/log/nft.log (события firewall) =="
        docker exec "$C" tail -n "$LINES" /var/log/nft.log 2>/dev/null || true
        ;;
    ids)
        echo "== ids: алерты Suricata =="
        docker exec "$C" tail -n "$LINES" /var/log/suricata/fast.log
        ;;
    ipa)
        echo "== ipa: журнал systemd =="
        docker exec "$C" journalctl -n "$LINES" --no-pager
        ;;
    vpn)
        echo "== vpn: журнал аутентификации =="
        docker exec "$C" tail -n "$LINES" /var/log/ovpn-auth.log 2>/dev/null || true
        echo "== vpn: лог процесса =="
        docker logs "$C" 2>&1 | tail -n "$LINES"
        ;;
    arm)
        echo "== arm: логи приложений (firefox/x11vnc) =="
        docker exec "$C" sh -c "tail -n $LINES /tmp/firefox.log /tmp/x11vnc.log 2>/dev/null" || true
        ;;
    *)
        echo "== $NODE: docker logs =="
        docker logs "$C" 2>&1 | tail -n "$LINES"
        ;;
esac
