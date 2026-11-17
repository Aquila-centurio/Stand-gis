# Suricata (IDS) для стенда — на основе официального образа jasonish/suricata.
FROM jasonish/suricata:latest

COPY entrypoint.sh /gis-entrypoint.sh
RUN chmod 0755 /gis-entrypoint.sh

ENTRYPOINT [ "/gis-entrypoint.sh" ]
