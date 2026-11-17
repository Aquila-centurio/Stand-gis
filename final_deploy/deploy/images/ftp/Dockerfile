# FTP (vsftpd) для ДМЗ.
# На базовом образе стенда + vsftpd. Обёртка настраивает сеть и запускает сервер.
FROM gis/linux:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends vsftpd passwd \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /gis-entrypoint.sh
RUN chmod 0755 /gis-entrypoint.sh

ENTRYPOINT [ "/gis-entrypoint.sh" ]
