#!/bin/sh
# Подключение к OpenVPN (LDAP-аутентификация через RADIUS).
# Бандл клиента монтируется в /etc/openvpn/client (ca.crt, client.ovpn, creds.txt).
exec openvpn --config /etc/openvpn/client/client.ovpn
