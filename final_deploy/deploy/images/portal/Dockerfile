# Captive-портал (NAS) для приватной сети.
FROM gis/linux:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /gis-entrypoint.sh
RUN chmod 0755 /gis-entrypoint.sh

ENTRYPOINT [ "/gis-entrypoint.sh" ]
