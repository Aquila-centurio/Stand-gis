# EML (postfix + dovecot) для ДМЗ.
FROM gis/linux:latest

RUN echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections \
 && echo "postfix postfix/mailname string mail.otlichnik.lab" | debconf-set-selections \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      postfix dovecot-imapd \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /gis-entrypoint.sh
RUN chmod 0755 /gis-entrypoint.sh

ENTRYPOINT [ "/gis-entrypoint.sh" ]
