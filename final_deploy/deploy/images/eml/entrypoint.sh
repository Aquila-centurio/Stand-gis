#!/bin/bash
# Обёртка ENTRYPOINT для EML (postfix + dovecot).
set -uo pipefail

ADDR="${ADDR:?ADDR не задан}"
GW="${GW:?GW не задан}"
MAIL_HOST="${MAIL_HOST:-mail.otlichnik.lab}"
MAIL_DOMAIN="${MAIL_DOMAIN:-otlichnik.lab}"
MAIL_USER="${MAIL_USER:-mailuser}"
MAIL_PASS="${MAIL_PASS:-mailpass}"

echo "[eml] ожидание eth1..."
while ! ip link show eth1 >/dev/null 2>&1; do sleep 1; done
ip link set eth1 up
ip addr add "$ADDR" dev eth1 2>/dev/null || true
ip route del default 2>/dev/null || true
ip route add default via "$GW" 2>/dev/null || true
if [ -n "${INTERNAL_NET:-}" ] && [ -n "${INTERNAL_GW:-}" ]; then
    ip route add "$INTERNAL_NET" via "$INTERNAL_GW" 2>/dev/null || true
fi
echo "nameserver 10.10.10.10" > /etc/resolv.conf

echo "[eml] ip route:"; ip route

# почтовый пользователь
if ! id "$MAIL_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$MAIL_USER"
    echo "${MAIL_USER}:${MAIL_PASS}" | chpasswd
fi
install -d -o "$MAIL_USER" -g "$MAIL_USER" "/home/${MAIL_USER}/Maildir" \
    "/home/${MAIL_USER}/Maildir/new" "/home/${MAIL_USER}/Maildir/cur" "/home/${MAIL_USER}/Maildir/tmp"

# postfix
echo "$MAIL_HOST" > /etc/mailname
if [ ! -s /etc/postfix/main.cf ]; then
    if [ -f /usr/share/postfix/main.cf.dist ]; then
        cp /usr/share/postfix/main.cf.dist /etc/postfix/main.cf
    else
        touch /etc/postfix/main.cf
    fi
fi
postconf -e "myhostname = ${MAIL_HOST}"
postconf -e "mydomain = ${MAIL_DOMAIN}"
postconf -e 'myorigin = $mydomain'
postconf -e 'inet_interfaces = all'
postconf -e 'inet_protocols = ipv4'
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e 'home_mailbox = Maildir/'
postconf -e 'mynetworks = 127.0.0.0/8, 10.10.0.0/16, 172.20.20.0/24'
postconf -e 'smtpd_use_tls = no'
postconf -e 'smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination'
postconf -e 'smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination'
postconf -e 'maillog_file = /dev/stdout'
newaliases 2>/dev/null || true
postfix check 2>/dev/null || true

# dovecot (IMAP, plaintext для лаборатории)
cat > /etc/dovecot/conf.d/99-gis.conf <<EOF
protocols = imap
disable_plaintext_auth = no
ssl = no
mail_location = maildir:~/Maildir
EOF

echo "[eml] запуск postfix и dovecot"
postfix start
dovecot

sleep 1
echo "[eml] готово; SMTP :25, IMAP :143"
exec sleep infinity
