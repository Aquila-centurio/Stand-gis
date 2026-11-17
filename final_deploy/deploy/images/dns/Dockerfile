# DNS-образ стенда: unbound (резолвер ДМЗ) и dnsmasq (внешний DNS-сервер).
FROM gis/linux:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      unbound \
      dnsmasq \
      dnsutils \
 && rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]
