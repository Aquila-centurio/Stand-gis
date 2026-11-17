#!/bin/bash
# Обёртка ENTRYPOINT для VPN (OpenVPN + RADIUS-аутентификация).
set -uo pipefail

ADDR="${ADDR:?ADDR не задан}"
GW="${GW:?GW не задан}"
RADIUS_SERVER="${RADIUS_SERVER:-10.10.10.15}"
RADIUS_SECRET="${RADIUS_SECRET:-testing123}"
VPN_NET="${VPN_NET:-10.8.0.0/24}"
VPN_PORT="${VPN_PORT:-1194}"

echo "[vpn] ожидание eth1..."
while ! ip link show eth1 >/dev/null 2>&1; do sleep 1; done
ip link set eth1 up
ip addr add "$ADDR" dev eth1 2>/dev/null || true
ip route del default 2>/dev/null || true
ip route add default via "$GW" 2>/dev/null || true
if [ -n "${INTERNAL_NET:-}" ] && [ -n "${INTERNAL_GW:-}" ]; then
    ip route add "$INTERNAL_NET" via "$INTERNAL_GW" 2>/dev/null || true
fi
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
echo "nameserver 10.10.10.10" > /etc/resolv.conf

echo "[vpn] ip route:"; ip route

OVPN=/etc/openvpn
mkdir -p "$OVPN/certs"

# --- PKI (генерируется один раз) ------------------------------------------
if [ ! -f "$OVPN/certs/ca.crt" ]; then
    echo "[vpn] генерация PKI"
    cat > "$OVPN/certs/server.ext" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:server.gis
EOF
    cat > "$OVPN/certs/client.ext" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature
extendedKeyUsage=clientAuth
subjectAltName=DNS:client.gis
EOF
    ( cd "$OVPN/certs"
      openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt \
          -days 3650 -subj "/CN=GIS-VPN-CA" \
          -addext "basicConstraints=critical,CA:TRUE" \
          -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1
      openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr \
          -subj "/CN=server.gis" >/dev/null 2>&1
      openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
          -out server.crt -days 3650 -extfile server.ext >/dev/null 2>&1
      openssl req -newkey rsa:2048 -nodes -keyout client.key -out client.csr \
          -subj "/CN=client.gis" >/dev/null 2>&1
      openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key \
          -out client.crt -days 3650 -extfile client.ext >/dev/null 2>&1 )
fi

# --- скрипт аутентификации через RADIUS -----------------------------------
cat > "$OVPN/auth-radius.sh" <<'EOF'
#!/bin/bash
# Логин/пароль приходят либо файлом (via-file, $1), либо через env (via-env).
LOG=/var/log/ovpn-auth.log
RADCLIENT="$(command -v radclient || echo /usr/bin/radclient)"
if [ -n "${1:-}" ] && [ -f "$1" ]; then
    user="$(sed -n '1p' "$1")"
    pass="$(sed -n '2p' "$1")"
else
    user="${username:-}"
    pass="${password:-}"
fi
{ echo "--- $(date) user='${user}' pass_len=${#pass} src=${1:-env} radclient=${RADCLIENT}"; } >> "$LOG" 2>&1
[ -z "$user" ] && { echo "no user" >> "$LOG"; exit 1; }
resp="$(echo "User-Name=${user},User-Password=${pass}" | "$RADCLIENT" -x -t 3 -r 1 "${RADIUS_SERVER:-10.10.10.15}:1812" auth "${RADIUS_SECRET:-testing123}" 2>&1)"
echo "$resp" >> "$LOG" 2>&1
echo "$resp" | grep -q "Access-Accept" && exit 0
exit 1
EOF
chmod 0755 "$OVPN/auth-radius.sh"

# --- конфигурация сервера -------------------------------------------------
cat > "$OVPN/server.conf" <<EOF
port ${VPN_PORT}
proto udp
dev tun
ca ${OVPN}/certs/ca.crt
cert ${OVPN}/certs/server.crt
key ${OVPN}/certs/server.key
dh none
topology subnet
server ${VPN_NET%/*} 255.255.255.0
ifconfig-pool-persist ${OVPN}/ipp.txt
push "route 10.10.20.0 255.255.255.0"
keepalive 10 60
auth-user-pass-verify ${OVPN}/auth-radius.sh via-file
script-security 2
username-as-common-name
verify-client-cert none
duplicate-cn
verb 3
EOF

# NAT для клиентского пула (чтобы отвечали узлы ДМЗ)
nft add table ip nat 2>/dev/null || true
nft add chain ip nat postrouting '{ type nat hook postrouting priority srcnat; policy accept; }' 2>/dev/null || true
nft add rule ip nat postrouting ip saddr ${VPN_NET} oifname eth1 masquerade 2>/dev/null || true

echo "[vpn] запуск openvpn на ${VPN_PORT}/udp, пул ${VPN_NET}"
exec openvpn --config "$OVPN/server.conf"
