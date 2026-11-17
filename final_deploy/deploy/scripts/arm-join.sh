#!/bin/sh
# Ввести АРМ (узел arm) в домен FreeIPA.
#
#   sh scripts/arm-join.sh
#
# В контейнере нет systemd, поэтому:
#   * hostnamectl/systemctl подменены заглушками в образе (иначе ipa-client-install падает);
#   * sssd после установки запускаем вручную.
set -eu
cd "$(dirname "$0")/.."

sudo docker exec clab-gis-arm bash -c '
set -e
export PATH=/usr/local/bin:$PATH

# собственная запись в /etc/hosts (на случай, если DNS ещё не отвечает)
grep -q "arm.otlichnik.lab" /etc/hosts || echo "10.10.20.12 arm.otlichnik.lab arm" >> /etc/hosts

if [ -f /etc/ipa/default.conf ]; then
    echo ">> АРМ уже в домене"
else
    ipa-client-install -U \
        --domain=otlichnik.lab --realm=OTLICHNIK.LAB \
        --server=ipa.otlichnik.lab --hostname=arm.otlichnik.lab \
        --mkhomedir --no-ntp --force-join \
        -p admin -w Secret123
fi

# sssd вручную (нет systemd)
mkdir -p /var/run/sssd /var/lib/sss/db /var/lib/sss/pipes /var/lib/sss/mc /var/log/sssd
pgrep -x sssd >/dev/null 2>&1 || sssd 2>/dev/null || true
sleep 1
echo ">> проверка домена:"
id testuser 2>/dev/null || getent passwd testuser || echo "  (sssd ещё поднимается — повторите id testuser)"
'
