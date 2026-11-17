#!/bin/sh
# Первичная настройка FreeIPA для RADIUS:
#  - сервисный bind-аккаунт radius (для поиска в LDAP)
#  - тестовый пользователь testuser (для проверки аутентификации)
# Запускать после того, как узел ipa полностью установлен.
set -eu
cd "$(dirname "$0")/.."

IPA() { sudo docker exec -i clab-gis-ipa "$@"; }

echo "== kinit admin =="
printf 'Secret123\n' | IPA kinit admin

echo "== bind-аккаунт radius =="
printf 'RadiusPass123\nRadiusPass123\n' \
    | IPA ipa user-add radius --first=Radius --last=Service --password || true

echo "== тестовый пользователь testuser =="
printf 'UserPass123\nUserPass123\n' \
    | IPA ipa user-add testuser --first=Test --last=User --password || true

echo "== проверка =="
IPA ipa user-find radius
IPA ipa user-find testuser

echo "== DNS-записи для АРМ (домен) =="
IPA ipa dnsrecord-add otlichnik.lab arm --a-rec=10.10.20.12 || true
IPA ipa dnsrecord-add 20.10.10.in-addr.arpa 12 --ptr-rec=arm.otlichnik.lab. || true
