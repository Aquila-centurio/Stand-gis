# FreeRADIUS с LDAP-бэкендом на FreeIPA.
# Обёртка ENTRYPOINT настраивает eth1 и раскладывает конфиги.
FROM freeradius/freeradius-server:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends iproute2 ldap-utils \
 && rm -rf /var/lib/apt/lists/* || true

COPY entrypoint.sh /gis-entrypoint.sh
RUN chmod 0755 /gis-entrypoint.sh

ENTRYPOINT [ "/gis-entrypoint.sh" ]
