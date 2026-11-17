#!/bin/sh
# Сборка образов стенда.
#
# Повторный запуск НЕ пересобирает уже собранные образы — это ускоряет
# поднятие стенда. Когда образ всё же не найден, docker использует
# кэш слоёв, поэтому пересобираются только затронутые слои.
#
#   sh scripts/build.sh                 # собрать только отсутствующие образы
#   sh scripts/build.sh --force         # пересобрать все образы
#   sh scripts/build.sh --force arm dns # пересобрать только arm и dns
#   sh scripts/build.sh arm             # собрать arm, если его ещё нет
#
# Порядок важен: dns/arm/eml/ftp/portal/vpn наследуются от gis/linux.
set -eu
cd "$(dirname "$0")/.."

usage() {
    cat <<'EOF'
Сборка образов стенда.

  sh scripts/build.sh [--force] [образ ...]

  --force, -f   пересобрать образы, даже если они уже существуют
  образ         имя образа без префикса gis/ (linux, arm, dns, ...)

Без аргументов собираются только отсутствующие образы всех узлов.
EOF
}

FORCE=0
REQUESTED=""
for a in "$@"; do
    case "$a" in
        -f|--force) FORCE=1 ;;
        -h|--help)  usage; exit 0 ;;
        -*)         echo "неизвестный флаг: $a" >&2; exit 2 ;;
        *)          REQUESTED="$REQUESTED $a" ;;
    esac
done

# Канонический порядок (учитывает зависимости от gis/linux).
ALL="linux dns ipa postgres freeradius web ftp eml vpn ids portal arm"
# Образы, которые собираются НАД gis/linux.
NEEDS_LINUX="dns eml ftp portal vpn arm"

[ -z "$REQUESTED" ] && REQUESTED="$ALL"

# Проверяем, что запрошенные образы существуют.
for r in $REQUESTED; do
    found=0
    for img in $ALL; do
        [ "$img" = "$r" ] && found=1 && break
    done
    [ "$found" -eq 1 ] || { echo "неизвестный образ: $r (доступны: $ALL)" >&2; exit 2; }
done

# Если запрошен зависимый образ, гарантируем сборку gis/linux первой.
for r in $REQUESTED; do
    for d in $NEEDS_LINUX; do
        [ "$r" = "$d" ] && REQUESTED="$REQUESTED linux"
    done
done

# Уникализуем и упорядочиваем согласно каноническому списку.
ORDER=""
for img in $ALL; do
    for r in $REQUESTED; do
        [ "$img" = "$r" ] && ORDER="$ORDER $img" && break
    done
done

for img in $ORDER; do
    tag="gis/$img:latest"
    if [ "$FORCE" -eq 0 ] && docker image inspect "$tag" >/dev/null 2>&1; then
        echo "   $tag — уже есть, пропуск (--force чтобы пересобрать)"
        continue
    fi
    echo ">> сборка $tag"
    docker build -t "$tag" "images/$img"
done
