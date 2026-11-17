#!/bin/sh
# Поднять стенд: собрать недостающие образы и развернуть топологию.
#
#   sh scripts/up.sh              # быстро: готовые образы не пересобираются
#   sh scripts/up.sh --rebuild    # пересобрать образы, затем развернуть
#
# Развёртывание идемпотентно: containerlab приводит уже развёрнутые узлы к
# состоянию топологии и не пересоздаёт их без необходимости.
# Тома ipa-data / vpn-data сохраняются между запусками.
set -eu
cd "$(dirname "$0")/.."
mkdir -p vpn-client          # каталог клиентского бандла (bind для ext-host/vpn-gui)

BUILD_ARGS=""
for a in "$@"; do
    case "$a" in
        --rebuild|-f|--force) BUILD_ARGS="$BUILD_ARGS --force" ;;
        -h|--help)
            cat <<'EOF'
Поднять стенд.

  sh scripts/up.sh [--rebuild]

  --rebuild      пересобрать образы перед развёртыванием
EOF
            exit 0 ;;
        *) BUILD_ARGS="$BUILD_ARGS $a" ;;
    esac
done

sh scripts/build.sh $BUILD_ARGS
sudo containerlab deploy -t topology.clab.yml
