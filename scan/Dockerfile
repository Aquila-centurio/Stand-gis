# Образ сканеров для аудита стенда: nmap и nikto.
# Запускается в сетевом пространстве нужного узла стенда:
#   docker run --rm --network container:clab-gis-<узел> --cap-add NET_RAW gis-scan <команда>
# Сборка: docker build -t gis-scan scan/
FROM debian:bookworm-slim

ARG NIKTO_TAG=2.6.1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      nmap perl libnet-ssleay-perl openssl libxml-writer-perl \
      curl ca-certificates iproute2 git \
 && git clone --depth 1 --branch "${NIKTO_TAG}" https://github.com/sullo/nikto /opt/nikto \
 && rm -rf /opt/nikto/.git \
 && apt-get purge -y --auto-remove git \
 && rm -rf /var/lib/apt/lists/*
