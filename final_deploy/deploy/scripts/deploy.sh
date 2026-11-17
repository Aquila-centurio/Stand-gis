#!/bin/sh
# Полное развёртывание стенда: сборка недостающих образов → деплой → настройка.
#
#   sh scripts/deploy.sh                 # готовые образы НЕ пересобираются
#   sh scripts/deploy.sh --rebuild       # пересобрать образы, затем развернуть
#   sh scripts/deploy.sh --skip-bootstrap # без первичной настройки IPA/VPN/АРМ
#
# Тома ipa-data / vpn-data НЕ удаляются (FreeIPA и PKI переиспользуются).
# Для полностью чистого прогона удалите их вручную и запустите deploy.sh снова:
#   sudo containerlab destroy -t topology.clab.yml --cleanup
#   docker volume rm ipa-data vpn-data
#   sh scripts/deploy.sh
set -eu
cd "$(dirname "$0")/.."

BUILD_ARGS=""
BOOTSTRAP=1
for a in "$@"; do
    case "$a" in
        --rebuild|-f|--force) BUILD_ARGS="$BUILD_ARGS --force" ;;
        --skip-bootstrap)     BOOTSTRAP=0 ;;
        -h|--help)
            cat <<'EOF'
Полное развёртывание стенда.

  sh scripts/deploy.sh [--rebuild] [--skip-bootstrap]

  --rebuild          пересобрать образы перед развёртыванием
  --skip-bootstrap   не выполнять первичную настройку (IPA/VPN/АРМ)
EOF
            exit 0 ;;
        *) BUILD_ARGS="$BUILD_ARGS $a" ;;
    esac
done

echo ">> [1/5] сборка образов (существующие пропускаются; --rebuild для пересборки)"
sh scripts/build.sh $BUILD_ARGS

echo ">> [2/5] каталог клиентского бандла VPN"
mkdir -p vpn-client

echo ">> [3/5] развёртывание стенда (идемпотентно)"
sudo containerlab deploy -t topology.clab.yml

if [ "$BOOTSTRAP" -eq 0 ]; then
    echo ">> [4/5]-[5/5] первичная настройка пропущена (--skip-bootstrap)"
    echo ">> готово."
    exit 0
fi

echo ">> [4/5] ожидание готовности FreeIPA (LDAP :389)"
i=0
while [ "$i" -lt 120 ]; do
    if sudo docker exec clab-gis-dns bash -c 'timeout 2 bash -c "exec 3<>/dev/tcp/10.10.20.10/389"' 2>/dev/null; then
        echo "   FreeIPA доступен"
        break
    fi
    i=$((i + 1)); sleep 5
done

echo ">> [5/5] первичная настройка (пользователи IPA, бандл VPN-клиента)"
sh scripts/ipa-bootstrap.sh || echo "   ВНИМАНИЕ: ipa-bootstrap.sh завершился с ошибкой — проверьте вручную"
sh scripts/vpn-client.sh --bundle-only || echo "   ВНИМАНИЕ: бандл VPN не собран — проверьте вручную"
sh scripts/arm-join.sh || echo "   ВНИМАНИЕ: ввод АРМ в домен не удался — проверьте вручную"

echo ">> готово. GUI:"
echo "   АРМ:        http://172.20.20.100:6080/vnc.html"
echo "   внешний:    http://172.20.20.101:6080/vnc.html"
