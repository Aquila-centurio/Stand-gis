# Базовый образ для узлов стенда (МЭ и хосты).
# debian:bookworm-slim не содержит ip/nft — ставим сетевые утилиты.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      iproute2 \
      nftables \
      iputils-ping \
      iputils-tracepath \
      tcpdump \
      dnsutils \
      netcat-openbsd \
      freeradius-utils \
      ulogd2 \
      curl \
      ca-certificates \
      procps \
 && rm -rf /var/lib/apt/lists/*

# Узлы containerlab должны продолжать работать после старта.
CMD ["sleep", "infinity"]
