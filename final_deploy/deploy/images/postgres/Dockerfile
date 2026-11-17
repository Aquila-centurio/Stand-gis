# Postgres для внутренней сети.
# Официальный образ + iproute2, чтобы containerlab мог выставить IP на eth1.
FROM postgres:16

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends iproute2 \
 && rm -rf /var/lib/apt/lists/*
