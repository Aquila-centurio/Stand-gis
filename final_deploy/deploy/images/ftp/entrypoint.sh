#!/bin/bash
# Обёртка ENTRYPOINT для FTP (vsftpd).
set -uo pipefail

ADDR="${ADDR:?ADDR не задан}"
GW="${GW:?GW не задан}"
FTP_USER="${FTP_USER:-ftpuser}"
FTP_PASS="${FTP_PASS:-ftppass}"
PASV_ADDRESS="${PASV_ADDRESS:-${ADDR%%/*}}"
PASV_MIN="${PASV_MIN:-30000}"
PASV_MAX="${PASV_MAX:-30009}"

echo "[ftp] ожидание eth1..."
while ! ip link show eth1 >/dev/null 2>&1; do sleep 1; done
ip link set eth1 up
ip addr add "$ADDR" dev eth1 2>/dev/null || true
ip route del default 2>/dev/null || true
ip route add default via "$GW" 2>/dev/null || true
if [ -n "${INTERNAL_NET:-}" ] && [ -n "${INTERNAL_GW:-}" ]; then
    ip route add "$INTERNAL_NET" via "$INTERNAL_GW" 2>/dev/null || true
fi
echo "nameserver 10.10.10.10" > /etc/resolv.conf

echo "[ftp] ip route:"; ip route

# локальный пользователь
if ! id "$FTP_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$FTP_USER"
    echo "${FTP_USER}:${FTP_PASS}" | chpasswd
fi
mkdir -p "/home/${FTP_USER}/pub"
echo "GIS FTP: файл-пример от $(date)" > "/home/${FTP_USER}/pub/readme.txt"
chown -R "$FTP_USER":"$FTP_USER" "/home/${FTP_USER}"

# vsftpd требует существующий secure_chroot_dir
mkdir -p /var/run/vsftpd/empty
chmod 755 /var/run/vsftpd/empty

cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=${PASV_MIN}
pasv_max_port=${PASV_MAX}
pasv_address=${PASV_ADDRESS}
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
seccomp_sandbox=NO
background=NO
EOF

echo "[ftp] запуск vsftpd (pasv ${PASV_MIN}-${PASV_MAX} @ ${PASV_ADDRESS})"
exec vsftpd /etc/vsftpd.conf
