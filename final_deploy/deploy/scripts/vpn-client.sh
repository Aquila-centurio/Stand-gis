#!/bin/sh
# Запуск тестового VPN-клиента ("удалённый пользователь") из внешнего сегмента.
#
# Использование:
#   sh scripts/vpn-client.sh [LOGIN] [PASSWORD] [--refresh-ca]
#   (по умолчанию: testuser / UserPass123)
#
# Клиентский бандл (ca.crt + конфиг + логин/пароль) хранится в ./vpn-client/
# и переиспользуется между запусками. Серверная PKI лежит в томе vpn-data,
# поэтому сертификат стабилен (генерируется один раз).
# Флаг --refresh-ca заново забирает ca.crt с сервера.
set -eu
cd "$(dirname "$0")/.."

USER="testuser"
PASS="UserPass123"
REFRESH=0
BUNDLE_ONLY=0
for a in "$@"; do
    case "$a" in
        --refresh-ca)  REFRESH=1 ;;
        --bundle-only) BUNDLE_ONLY=1 ;;
        *) if [ "$USER" = "testuser" ]; then USER="$a"; else PASS="$a"; fi ;;
    esac
done

CDIR="./vpn-client"
mkdir -p "$CDIR"

if [ ! -s "$CDIR/ca.crt" ] || [ "$REFRESH" = "1" ]; then
    echo ">> получаю ca.crt с VPN-сервера"
    docker exec clab-gis-vpn cat /etc/openvpn/certs/ca.crt > "$CDIR/ca.crt"
fi

cat > "$CDIR/client.ovpn" <<'EOF'
client
dev tun
proto udp
remote 10.10.10.14 1194
ca /etc/openvpn/client/ca.crt
auth-user-pass /etc/openvpn/client/creds.txt
remote-cert-tls server
verb 3
EOF
printf '%s\n%s\n' "$USER" "$PASS" > "$CDIR/creds.txt"

if [ "$BUNDLE_ONLY" = "1" ]; then
    echo ">> клиентский бандл готов: $CDIR (ca.crt, client.ovpn, creds.txt)"
    exit 0
fi

exec docker run --rm -it \
    --network container:clab-gis-ext-host \
    --cap-add NET_ADMIN --device /dev/net/tun \
    -v "$(pwd)/${CDIR#./}":/etc/openvpn/client:ro,z \
    kylemanna/openvpn openvpn --config /etc/openvpn/client/client.ovpn
